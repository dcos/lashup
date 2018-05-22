-module(lashup_kv).
-author("sdhillon").
-behaviour(gen_server).

-include_lib("stdlib/include/ms_transform.hrl").
-include("lashup_kv.hrl").

%% API
-export([
  start_link/0,
  request_op/2,
  request_op/3,
  keys/1,
  value/1,
  value2/1,
  dirty_get_lclock/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
  handle_info/2, terminate/2, code_change/3]).

-export_type([key/0]).

-define(INIT_LCLOCK, -1).
-define(WARN_OBJECT_SIZE_MB, 60).
-define(REJECT_OBJECT_SIZE_MB, 100).
-define(MAX_MESSAGE_QUEUE_LEN, 32).
-define(KV_TOPIC, lashup_kv_20161114).

-record(state, {
  mc_ref = erlang:error() :: reference()
}).


-spec(request_op(Key :: key(), Op :: riak_dt_map:map_op()) ->
  {ok, riak_dt_map:value()} | {error, Reason :: term()}).
request_op(Key, Op) ->
  request_op(Key, undefined, Op).

-spec(request_op(Key :: key(), Context :: riak_dt_vclock:vclock() | undefined, Op :: riak_dt_map:map_op()) ->
  {ok, riak_dt_map:value()} | {error, Reason :: term()}).
request_op(Key, VClock, Op) ->
  Pid = whereis(?MODULE),
  Args = {op, Key, VClock, Op},
  MaxMsgQueueLen = max_message_queue_len(),
  try erlang:process_info(Pid, message_queue_len) of
    {message_queue_len, MsgQueueLen} when MsgQueueLen > MaxMsgQueueLen ->
      {error, overflow};
    {message_queue_len, _MsgQueueLen} ->
      gen_server:call(Pid, Args, infinity)
  catch error:badarg ->
    exit({noproc, {gen_server, call, [?MODULE, Args]}})
  end.

-spec(keys(ets:match_spec()) -> [key()]).
keys(MatchSpec) ->
  op_getkeys(MatchSpec).

-spec(value(Key :: key()) -> riak_dt_map:value()).
value(Key) ->
  {_, KV} = op_getkv(Key),
  riak_dt_map:value(KV#kv2.map).


-spec(value2(Key :: key()) -> {riak_dt_map:value(), riak_dt_vclock:vclock()}).
value2(Key) ->
  {_, KV} = op_getkv(Key),
  {riak_dt_map:value(KV#kv2.map), KV#kv2.vclock}.

-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  set_off_heap(),
  init_db(),
  %% Maybe read_concurrency?
  {ok, Reference} = lashup_gm_mc_events:subscribe([?KV_TOPIC]),
  State = #state{mc_ref = Reference},
  {ok, State}.

handle_call({op, Key, VClock, Op}, _From, State) ->
  {Reply, State1} = handle_op(Key, Op, VClock, State),
  {reply, Reply, State1};
handle_call({start_kv_sync_fsm, RemoteInitiatorNode, RemoteInitiatorPid}, _From, State) ->
  Result = lashup_kv_aae_sup:receive_aae(RemoteInitiatorNode, RemoteInitiatorPid),
  {reply, Result, State};
handle_call(_Request, _From, State) ->
  {reply, {error, unknown_request}, State}.

%% A maybe update from the sync FSM
handle_cast({maybe_update, Key, VClock, Map}, State0) ->
  State1 = handle_full_update(#{key => Key, vclock => VClock, map => Map}, State0),
  {noreply, State1};
handle_cast(_Request, State) ->
  {noreply, State}.

handle_info({lashup_gm_mc_event, Event = #{ref := Ref}}, State = #state{mc_ref = Ref}) ->
  MaxMsgQueueLen = max_message_queue_len(),
  case erlang:process_info(self(), message_queue_len) of
    {message_queue_len, MsgQueueLen} when MsgQueueLen > MaxMsgQueueLen ->
      lager:error("lashup_kv: message box is overflowed, ~p", [MsgQueueLen]),
      {noreply, State};
    {message_queue_len, _MsgQueueLen} ->
      State1 = handle_lashup_gm_mc_event(Event, State),
      {noreply, State1}
  end;
handle_info(Info, State) ->
  lager:debug("Info: ~p", [Info]),
  {noreply, State}.

terminate(Reason, State) ->
  lager:debug("Terminating for reason: ~p, in state: ~p", [Reason, lager:pr(State, ?MODULE)]),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal types
%%%===================================================================

-type kv() :: #kv2{}.
-type state() :: #state{}.
-type nclock() :: #nclock{}.
-type lclock() :: non_neg_integer().
-type tables() :: list().

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec(max_message_queue_len() -> pos_integer()).
max_message_queue_len() ->
  application:get_env(lashup, max_message_queue_len, ?MAX_MESSAGE_QUEUE_LEN).

-spec(set_off_heap() -> on_heap | off_heap).
set_off_heap() ->
  try
    % Garbage collection with many messages placed on the heap can become
    % extremely expensive and the process can consume large amounts of memory.
    erlang:process_flag(message_queue_data, off_heap)
  catch error:badarg ->
    % off_heap options is avaliable in OTP 20.0-rc2 and later
    off_heap
  end.

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
  Tables = [?KV_TABLE, nclock],
  TablesToCreate = Tables -- ExistingTables,
  Alltables = TablesToCreate ++ ExistingTables,
  lists:foreach(fun create_table/1, TablesToCreate),
  case mnesia:wait_for_tables(Alltables, 60000) of
    ok ->
      ok = maybe_upgrade_table(ExistingTables);
    {timeout, BadTables} ->
      lager:alert("Couldn't initialize mnesia tables: ~p", [BadTables]),
      init:stop(1);
    {error, Error} ->
      lager:alert("Couldn't initialize mnesia tables: ~p", [Error]),
      init:stop(1)
  end.

create_table(Table) ->
  {atomic, ok} =  mnesia:create_table(Table, [
    {attributes, get_record_info(Table)},
    {disc_copies, [node()]},
    {type, set}
  ]).

get_record_info(kv2) ->
  record_info(fields, kv2);
get_record_info(nclock) ->
  record_info(fields, nclock).

-spec(maybe_upgrade_table(tables()) -> ok|aborted).
maybe_upgrade_table(ExistingTables) ->
  case {lists:member(?KV_TABLE, ExistingTables), lists:member(?OLD_KV_TABLE, ExistingTables)} of
    {true, _} ->
        ok; %% already upgraded
    {false, false} ->
        ok; %% nothing to upgrade
    {false, true} ->
        upgrade_table(kv)
  end.

-spec(upgrade_table(kv) -> ok|aborted).
upgrade_table(kv) ->
  F = fun() ->
        LClock = mnesia:foldl(fun convert_and_write_record/2, ?INIT_LCLOCK, ?OLD_KV_TABLE),
        NClock = #nclock{key = node(), lclock = LClock},
        mnesia:write(NClock)
      end,
  case mnesia:sync_transaction(F) of
    {atomic, _} ->
      ok = mnesia:sync_log();
    {aborted, Reason} ->
      lager:error("Failed to upgrade kv table because ~p", [Reason]),
      aborted
  end.

convert_and_write_record(Record0, Counter0) ->
    Counter1 = Counter0 + 1,
    Record1 = convert_record(Record0, Counter1),
    mnesia:write(Record1),
    Counter1.

convert_record(_R = #kv{key = Key, vclock = VClock, map = Map}, Counter) ->
  #kv2{key = Key, vclock = VClock, map = Map, lclock = Counter}.

-spec(mk_write_fun(Key :: key(), OldVClock :: riak_dt_vclock:vclock() | undefined,
      Op :: riak_dt_map:map_op()) -> (fun())).
mk_write_fun(Key, OldVClock, Op) ->
  fun() ->
    {NewKV, NClock} =
      case mnesia:read(?KV_TABLE, Key, write) of
        [] ->
          prepare_kv(Key, riak_dt_map:new(), riak_dt_vclock:fresh(), Op);
        [#kv2{vclock = VClock}] when OldVClock =/= undefined andalso VClock =/= OldVClock ->
          mnesia:abort(concurrency_violation);
        [#kv2{vclock = VClock, map = Map}] ->
          prepare_kv(Key, Map, VClock, Op)
      end,
    case check_map(NewKV) of
      {error, Error} ->
        mnesia:abort(Error);
      ok ->
        mnesia:write(NewKV),
        mnesia:write(NClock)
    end,
    NewKV
  end.

-spec(prepare_kv(Key :: key(), Map0 :: riak_dt_map:dt_map(), VClock0 :: riak_dt_vclock:vclock() | undefined,
      Op :: riak_dt_map:map_op()) -> {kv(), nclock()}).
prepare_kv(Key, Map0, VClock0, Op) ->
  Node = node(),
  VClock1 = riak_dt_vclock:increment(Node, VClock0),
  Counter = riak_dt_vclock:get_counter(Node, VClock1),
  Dot = {Node, Counter},
  Map2 =
    case riak_dt_map:update(Op, Dot, Map0) of
      {ok, Map1} -> Map1;
      {error, {precondition, {not_present, _Field}}} -> Map0
    end,
  LClock0 = get_lclock(Node),
  LClock1 = increment_lclock(LClock0),
  {#kv2{key = Key, vclock = VClock1, map = Map2, lclock = LClock1},
   #nclock{key = Node, lclock = LClock1}}.

-spec handle_op(Key :: term(), Op :: riak_dt_map:map_op(), OldVClock :: riak_dt_vclock:vclock() | undefined,
    State :: state()) -> {Reply :: term(), State1 :: state()}.
handle_op(Key, Op, OldVClock, State) ->
  %% We really want to make sure this persists and we don't have backwards traveling clocks
  Fun = mk_write_fun(Key, OldVClock, Op),
  case mnesia:sync_transaction(Fun) of
    {atomic, NewKV} ->
      ok = mnesia:sync_log(),
      dumped = mnesia:dump_log(),
      propagate(NewKV),
      NewValue = riak_dt_map:value(NewKV#kv2.map),
      {{ok, NewValue}, State};
    {aborted, Reason} ->
      {{error, Reason}, State}
  end.

%% TODO: Add metrics
-spec(check_map(kv()) -> {error, Reason :: term()} | ok).
check_map(NewKV = #kv2{key = Key}) ->
  case erlang:external_size(NewKV) of
    Size when Size > ?REJECT_OBJECT_SIZE_MB * 1000000 ->
      {error, value_too_large};
    Size when Size > (?WARN_OBJECT_SIZE_MB + ?REJECT_OBJECT_SIZE_MB) / 2 * 1000000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes (REJECTION IMMINENT)", [Key, Size]),
      ok;
    Size when Size > ?WARN_OBJECT_SIZE_MB * 1000000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes", [Key, Size]),
      ok;
    _ ->
      ok
  end.

-spec (propagate(kv()) -> ok).
propagate(_KV = #kv2{key = Key, map = Map, vclock = VClock}) ->
  Payload = #{type => full_update, reason => op, key => Key, map => Map, vclock => VClock},
  lashup_gm_mc:multicast(?KV_TOPIC, Payload),
  ok.

% @private either gets the KV object for a given key, or returns an empty one
-spec(op_getkv(key()) -> {new, kv()} | {existing, kv()}).
op_getkv(Key) ->
  case mnesia:dirty_read(?KV_TABLE, Key) of
    [] ->
      {new, #kv2{key = Key}};
    [KV] ->
      {existing, KV}
  end.

-spec(op_getkeys(ets:match_spec()) -> [key()]).
op_getkeys(MatchSpec) ->
  Keys = mnesia:dirty_all_keys(?KV_TABLE),
  MatchSpecCompiled = ets:match_spec_compile(MatchSpec),
  [Key || Key <- Keys, [true] == ets:match_spec_run([{Key}], MatchSpecCompiled)].

-spec(dirty_get_lclock(node()) -> lclock()).
dirty_get_lclock(Key) ->
  get_lclock(fun mnesia:dirty_read/2, Key).

-spec(get_lclock(node()) -> lclock()).
get_lclock(Key) ->
  get_lclock(fun mnesia:read/2, Key).

-spec(get_lclock(fun(), node()) -> lclock()).
get_lclock(READ, Key) ->
  case READ(nclock, Key) of
    [] ->
      ?INIT_LCLOCK;
    [#nclock{lclock = LClock}] ->
      LClock
  end.

-spec(handle_lashup_gm_mc_event(map(), state()) -> state()).
handle_lashup_gm_mc_event(#{payload := #{type := full_update} = Payload}, State) ->
  handle_full_update(Payload, State);
handle_lashup_gm_mc_event(Payload, State) ->
  lager:debug("Unknown GM MC event: ~p", [Payload]),
  State.

-spec(mk_full_update_fun(Key :: key(),  RemoteMap :: riak_dt_map:dt_map(),
       RemoteVClock :: riak_dt_vclock:vclock())
       -> fun(() -> kv())).
mk_full_update_fun(Key, RemoteMap, RemoteVClock) ->
  fun() ->
    case mnesia:read(?KV_TABLE, Key, write) of
      [] ->
        LClock0 = get_lclock(node()),
        LClock1 = increment_lclock(LClock0),
        KV = #kv2{key = Key, vclock = RemoteVClock, map = RemoteMap, lclock = LClock1},
        NClock = #nclock{key = node(), lclock = LClock1},
        ok = mnesia:write(KV),
        ok = mnesia:write(NClock),
        KV;
      [KV] ->
        maybe_full_update(should_full_update(KV, RemoteMap, RemoteVClock))
    end
  end.

-spec(maybe_full_update({true | false, kv(), nclock()}) -> kv()).
maybe_full_update({false, KV, _}) ->
  KV;
maybe_full_update({true, KV, NClock}) ->
  ok = mnesia:write(KV),
  ok = mnesia:write(NClock),
  KV.

-spec(should_full_update(LocalKV :: kv(), RemoteMap :: riak_dt_map:dt_map(),
        RemoteVClock :: riak_dt_vclock:vclock())
          -> {true | false, kv(), nclock()}).
should_full_update(LocalKV = #kv2{vclock = LocalVClock}, RemoteMap, RemoteVClock) ->
  case {riak_dt_vclock:descends(RemoteVClock, LocalVClock), riak_dt_vclock:descends(LocalVClock, RemoteVClock)} of
    {true, false} ->
      create_full_update(LocalKV, RemoteMap, RemoteVClock);
    {false, false} ->
      create_full_update(LocalKV, RemoteMap, RemoteVClock);
    %% Either they are equal, or the local one is newer - perhaps trigger AAE?
    _ ->
      LClock0 = get_lclock(node()),
      LClock1 = increment_lclock(LClock0),
      NClock = #nclock{key = node(), lclock = LClock1},
      {false, LocalKV, NClock}
  end.

-spec(create_full_update(LocalKV :: kv(), RemoteMap :: riak_dt_map:dt_map(),
        RemoteVClock :: riak_dt_vclock:vclock()) ->
  {true, kv(), nclock()}).
create_full_update(KV = #kv2{vclock = LocalVClock}, RemoteMap, RemoteVClock) ->
  Map1 = riak_dt_map:merge(RemoteMap, KV#kv2.map),
  VClock1 = riak_dt_vclock:merge([LocalVClock, RemoteVClock]),
  LClock0 = get_lclock(node()),
  LClock1 = increment_lclock(LClock0),
  KV1 = KV#kv2{map = Map1, vclock = VClock1, lclock = LClock1},
  NClock = #nclock{key = node(), lclock = LClock1},
  {true, KV1, NClock}.

-spec(handle_full_update(map(), state()) -> state()).
handle_full_update(_Payload = #{key := Key, vclock := RemoteVClock, map := RemoteMap}, State) ->
  Fun = mk_full_update_fun(Key, RemoteMap, RemoteVClock),
  {atomic, _} = mnesia:sync_transaction(Fun),
  State.

increment_lclock(N) ->
  N + 1.
