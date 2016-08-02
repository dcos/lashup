%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. Feb 2016 6:16 PM
%%%-------------------------------------------------------------------

%% TODO:
%% -Add VClock pruning

-module(lashup_kv).
-author("sdhillon").

-behaviour(gen_server).

-include_lib("stdlib/include/ms_transform.hrl").
-include_lib("stdlib/include/qlc.hrl").

%% API
-export([
  start_link/0,
  request_op/2,
  request_op/3,
  value/1,
  value2/1
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-export_type([key/0]).

-define(SERVER, ?MODULE).

-define(WARN_OBJECT_SIZE_KB, 25).
-define(REJECT_OBJECT_SIZE_KB, 100).

-record(state, {
  mc_ref = erlang:error() :: reference()
}).


-include("lashup_kv.hrl").
-type kv() :: #kv{}.
-type state() :: #state{}.


%%%===================================================================
%%% API
%%%===================================================================

-spec(request_op(Key :: key(), Op :: riak_dt_map:map_op()) ->
  {ok, riak_dt_map:value()} | {error, Reason :: term()}).
request_op(Key, Op) ->
  gen_server:call(?SERVER, {op, Key, Op}).


-spec(request_op(Key :: key(), Context :: riak_dt_vclock:vclock(), Op :: riak_dt_map:map_op()) ->
  {ok, riak_dt_map:value()} | {error, Reason :: term()}).
request_op(Key, VClock, Op) ->
  gen_server:call(?SERVER, {op, Key, VClock, Op}).

-spec(value(Key :: key()) -> riak_dt_map:value()).
value(Key) ->
  {_, KV} = op_getkv(Key),
  riak_dt_map:value(KV#kv.map).


-spec(value2(Key :: key()) -> {riak_dt_map:value(), riak_dt_vclock:vclock()}).
value2(Key) ->
  {_, KV} = op_getkv(Key),
  {riak_dt_map:value(KV#kv.map), KV#kv.vclock}.

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: state()} | {ok, State :: state(), timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  init_db(),
  %% Maybe read_concurrency?
  {ok, Reference} = lashup_gm_mc_events:subscribe([?MODULE]),
  State = #state{mc_ref = Reference},
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
  State :: state()) ->
  {reply, Reply :: term(), NewState :: state()} |
  {reply, Reply :: term(), NewState :: state(), timeout() | hibernate} |
  {noreply, NewState :: state()} |
  {noreply, NewState :: state(), timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: state()} |
  {stop, Reason :: term(), NewState :: state()}).
handle_call({op, Key, VClock, Op}, _From, State) ->
  {Reply, State1} = handle_op(Key, Op, VClock, State),
  {reply, Reply, State1};
handle_call({op, Key, Op}, _From, State) ->
  {Reply, State1} = handle_op(Key, Op, undefined, State),
  {reply, Reply, State1};
handle_call({start_kv_sync_fsm, RemoteInitiatorNode, RemoteInitiatorPid}, _From, State) ->
  Result = lashup_kv_aae_sup:receive_aae(RemoteInitiatorNode, RemoteInitiatorPid),
  {reply, Result, State};
handle_call(_Request, _From, State) ->
  {reply, {error, unknown_request}, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: state()) ->
  {noreply, NewState :: state()} |
  {noreply, NewState :: state(), timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: state()}).
%% A maybe update from the sync FSM
handle_cast({maybe_update, Key, VClock, Map}, State0) ->
  State1 = handle_full_update(#{key => Key, vclock => VClock, map => Map}, State0),
  {noreply, State1};
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: state()) ->
  {noreply, NewState :: state()} |
  {noreply, NewState :: state(), timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: state()}).
handle_info({lashup_gm_mc_event, Event = #{ref := Ref}}, State = #state{mc_ref = Ref}) ->
  State1 = handle_lashup_gm_mc_event(Event, State),
  {noreply, State1};
handle_info(Info, State) ->
  lager:debug("Info: ~p", [Info]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
  State :: state()) -> term()).
terminate(Reason, State) ->
  lager:debug("Terminating for reason: ~p, in state: ~p", [Reason, lager:pr(State, ?MODULE)]),
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: state(),
  Extra :: term()) ->
  {ok, NewState :: state()} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% Mostly borrowed from: https://github.com/ChicagoBoss/ChicagoBoss/wiki/Automatic-schema-initialization-for-mnesia
-spec(init_db() -> ok).
init_db() ->
  init_db([node()]).

-spec(init_db([node()]) -> ok).
init_db(Nodes) ->
  mnesia:create_schema(Nodes),
  mnesia:change_table_copy_type (schema, node(), disc_copies), % If the node was already running
  {ok, _} = application:ensure_all_started(mnesia),
  ExistingTables = mnesia:system_info(tables),
  Tables = [kv],
  TablesToCreate = Tables -- ExistingTables,
  lists:foreach(fun create_table/1, TablesToCreate),
  ok = mnesia:wait_for_tables(Tables, 5000).

create_table(kv) ->
  {atomic, ok} =  mnesia:create_table(kv, [
    {attributes, record_info(fields, kv)},
    {disc_copies, [node()]},
    {type, ordered_set}
  ]).


-spec(mk_write_fun(Key :: key(), OldVClock :: riak_dt_vclock:vclock() | undefined, Op :: riak_dt_map:map_op())
      -> (fun())).
mk_write_fun(Key, OldVClock, Op) ->
  Node = node(),
  fun() ->
    NewKV =
      case mnesia:read(kv, Key, write) of
        [] ->
          VClock = riak_dt_vclock:increment(Node, riak_dt_vclock:fresh()),
          Counter = riak_dt_vclock:get_counter(Node, VClock),
          Dot = {Node, Counter},
          {ok, Map} = riak_dt_map:update(Op, Dot, riak_dt_map:new()),
          #kv{key = Key, vclock = VClock, map = Map};
        [_ExistingKV = #kv{vclock = VClock}] when OldVClock =/= undefined andalso VClock =/= OldVClock ->
          mnesia:abort(concurrency_violation);
        [ExistingKV = #kv{vclock = VClock, map = Map}] ->
          VClock1 = riak_dt_vclock:increment(Node, VClock),
          Counter = riak_dt_vclock:get_counter(Node, VClock1),
          Dot = {Node, Counter},
          {ok, Map1} = riak_dt_map:update(Op, Dot, Map),
          ExistingKV#kv{vclock = VClock1, map = Map1}
      end,
    case check_map(NewKV) of
      {error, Error} ->
        mnesia:abort(Error);
      ok ->
        mnesia:write(NewKV)
    end,
    NewKV
  end.

-spec handle_op(Key :: term(), Op :: riak_dt_map:map_op(), OldVClock :: riak_dt_vclock:vclock() | undefined,
    State :: state()) -> {Reply :: term(), State1 :: state()}.
handle_op(Key, Op, OldVClock, State0) ->
  Fun = mk_write_fun(Key, OldVClock, Op),
  case mnesia:sync_transaction(Fun) of
    {atomic, #kv{} = NewKV} ->
      ok = mnesia:sync_log(),
      dumped = mnesia:dump_log(),
      propagate(NewKV),
      NewValue = riak_dt_map:value(NewKV#kv.map),
      {{ok, NewValue}, State0};
    {aborted, Reason} ->
      {{error, Reason}, State0}
  end.
  %% We really want to make sure this persists and we don't have backwards traveling clocks




%% TODO: Add metrics
-spec(check_map(kv()) -> {error, Reason :: term()} | ok).
check_map(NewKV = #kv{key = Key}) ->
  case size(erlang:term_to_binary(NewKV, [compressed])) of
    Size when Size > ?REJECT_OBJECT_SIZE_KB * 10000 ->
      {error, value_too_large};
    Size when Size > (?WARN_OBJECT_SIZE_KB + ?REJECT_OBJECT_SIZE_KB) / 2 * 10000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes (REJECTION IMMINENT)", [Key, Size]),
      ok;
    Size when Size > ?WARN_OBJECT_SIZE_KB * 10000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes", [Key, Size]),
      ok;
    _ ->
      ok
  end.

-spec (propagate(kv()) -> ok).
propagate(_KV = #kv{key = Key, map = Map, vclock = VClock}) ->
  Payload = #{type => full_update, reason => op, key => Key, map => Map, vclock => VClock},
  lashup_gm_mc:multicast(?MODULE, Payload),
  ok.

% @private either gets the KV object for a given key, or returns an empty one
-spec(op_getkv(key()) -> {new, kv()} | {existing, kv()}).
op_getkv(Key) ->
  case mnesia:dirty_read(kv, Key) of
    [] ->
      {new, #kv{key = Key}};
    [KV] ->
      {existing, KV}
  end.



-spec(handle_lashup_gm_mc_event(map(), state()) -> state()).
handle_lashup_gm_mc_event(#{payload := #{type := full_update} = Payload}, State) ->
  handle_full_update(Payload, State);
handle_lashup_gm_mc_event(Payload, State) ->
  lager:debug("Unknown GM MC event: ~p", [Payload]),
  State.

-spec(mk_full_update_fun(Key :: key(),  RemoteMap :: riak_dt_map:dt_map(), RemoteVClock :: riak_dt_vclock:vclock())
      -> fun(() -> kv())).
mk_full_update_fun(Key, RemoteMap, RemoteVClock) ->
  fun() ->
    case mnesia:read(kv, Key, write) of
      [] ->
        ok = mnesia:write(KV = #kv{key = Key, vclock = RemoteVClock, map = RemoteMap}),
        KV;
      [KV] ->
        maybe_full_update(should_full_update(KV, RemoteMap, RemoteVClock))
    end
  end.
-spec(maybe_full_update({true | false, kv()}) -> kv()).
maybe_full_update({false, KV}) ->
  KV;
maybe_full_update({true, KV}) ->
  ok = mnesia:write(KV),
  KV.

-spec(should_full_update(LocalKV :: kv(), RemoteMap :: riak_dt_map:dt_map(), RemoteVClock :: riak_dt_vclock:vclock())
    -> {true | false, kv()}).
should_full_update(LocalKV = #kv{vclock = LocalVClock}, RemoteMap, RemoteVClock) ->
  case {riak_dt_vclock:descends(RemoteVClock, LocalVClock), riak_dt_vclock:descends(LocalVClock, RemoteVClock)} of
    {true, false} ->
      create_full_update(LocalKV, RemoteMap, RemoteVClock);
    {false, false} ->
      create_full_update(LocalKV, RemoteMap, RemoteVClock);
    %% Either they are equal, or the local one is newer - perhaps trigger AAE?
    _ ->
      {false, LocalKV}
  end.
-spec(create_full_update(LocalKV :: kv(), RemoteMap :: riak_dt_map:dt_map(), RemoteVClock :: riak_dt_vclock:vclock()) ->
  {true, kv()}).
create_full_update(KV = #kv{vclock = LocalVClock}, RemoteMap, RemoteVClock) ->
  Map1 = riak_dt_map:merge(RemoteMap, KV#kv.map),
  VClock1 = riak_dt_vclock:merge([LocalVClock, RemoteVClock]),
  KV1 = KV#kv{map = Map1, vclock = VClock1},
  {true, KV1}.

-spec(handle_full_update(map(), state()) -> state()).
handle_full_update(_Payload = #{key := Key, vclock := RemoteVClock, map := RemoteMap}, State0) ->
  Fun = mk_full_update_fun(Key, RemoteMap, RemoteVClock),
  {atomic, _} = mnesia:sync_transaction(Fun),
  State0.
