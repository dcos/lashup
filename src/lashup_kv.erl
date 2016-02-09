%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. Feb 2016 6:16 PM
%%%-------------------------------------------------------------------
-module(lashup_kv).
-author("sdhillon").

-behaviour(gen_server).

-include_lib("stdlib/include/ms_transform.hrl").
-include_lib("stdlib/include/qlc.hrl").

%% API
-export([
  start_link/0,
  request_op/2,
  value/1
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(MAX_AAE_REPLIES, 10).

-define(WARN_OBJECT_SIZE_KB, 25).
-define(REJECT_OBJECT_SIZE_KB, 100).


-type actor_id() :: {Node :: node(), Uid :: integer()}.
-record(state, {
  mc_ref = erlang:error() :: reference(),
  actor_id = erlang:error() :: actor_id()
}).

-record(kv, {
  key = erlang:error() :: key(),
  map = riak_dt_delta_map:new() :: riak_dt_delta_map:delta_map(),
  vclock = vclock:fresh() :: vclock:vclock()
}).

-type key() :: term().
-type kv() :: #kv{}.
-type state() :: #state{}.

%%%===================================================================
%%% API
%%%===================================================================

-spec(request_op(Key :: key(), Op :: riak_dt_delta_map:map_op()) -> term()).
request_op(Key, Op) ->
  gen_server:call(?SERVER, {op, Key, Op}).

-spec(value(Key :: key()) -> term()).
value(Key) ->
  KV = op_getkv(Key),
  riak_dt_delta_map:value(KV#kv.map).

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
  lashup_utils:wakeup_loop(aae_wakeup, lashup_utils:linear_ramp_up(fun lashup_config:aae_interval/0, 10)),
  random:seed(lashup_utils:seed()),
  ?MODULE = ets:new(?MODULE, [ordered_set, named_table, {keypos, #kv.key}]),
  {ok, Reference} = lashup_gm_mc_events:subscribe([?MODULE]),
  ActorID = {node(), erlang:unique_integer()},
  State = #state{mc_ref = Reference, actor_id = ActorID},
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
handle_call({op, Key, Op}, _From, State) ->
  {Reply, State1} = op(Key, Op, State),
  {reply, Reply, State1};
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

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
handle_info(aae_wakeup, State) ->
  State1 = handle_aae_wakeup(State),
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
terminate(_Reason, _State) ->
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

-spec op(Key :: term(), Op :: riak_dt_delta_map:map_op(), State :: state()) -> {Reply :: term(), State1 :: state()}.
op(Key, Op, State) ->
  KV = op_getkv(Key),
  chk_op(op_perform(KV, Op, State), State).

chk_op(OpStatus = {ok, NewKV = #kv{key = Key}, _Delta}, State) ->
  case erlang:external_size(NewKV) of
    Size when Size > ?REJECT_OBJECT_SIZE_KB * 10000 ->
      {{error, value_too_large}, State};
    Size when Size > (?WARN_OBJECT_SIZE_KB + ?REJECT_OBJECT_SIZE_KB) / 2 * 10000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes (REJECTION IMMINENT)", [Key, Size]),
      commit_op(OpStatus, State);
    Size when Size > ?WARN_OBJECT_SIZE_KB * 10000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes", [Key, Size]),
      commit_op(OpStatus, State)
  end.

commit_op({ok, NewKV = #kv{map = Map}, Delta}, State) ->
  ets:insert(?MODULE, NewKV),
  propagate(NewKV, Delta),
  NewValue = riak_dt_delta_map:value(Map),
  {{ok, NewValue}, State}.

propagate(_KV = #kv{key = Key, vclock = VClock}, Delta) ->
  Payload = #{type => delta_update, key => Key, vclock => VClock, delta => Delta},
  lashup_gm_mc:multicast(?MODULE, Payload).

op_getkv(Key) ->
  case ets:lookup(?MODULE, Key) of
    [] ->
      #kv{key = Key};
    [KV] ->
      KV
  end.

-spec(op_perform(KV :: kv(), Op :: riak_dt_delta_map:map_op(), State :: state()) ->
    {ok, KV1 :: kv(), Delta :: riak_dt_delta_map:delta_map()}).
op_perform(KV = #kv{vclock = VClock, map = Map}, Op, _State = #state{actor_id = ActorID}) ->
  Now = erlang:system_time(nano_seconds),
  VClock1 = vclock:increment(ActorID, Now, VClock),
  {ok, ImpureDot} = vclock:get_dot(ActorID, VClock1),
  Dot = vclock:pure_dot(ImpureDot),
  KV1 = KV#kv{vclock = VClock1},
  op_perform(KV1, riak_dt_delta_map:delta_update(Op, Dot, Map)).

op_perform(KV = #kv{map = Map}, {ok, Delta}) ->
  Map1 = riak_dt_delta_map:merge(Map, Delta),
  {ok, KV#kv{map = Map1}, Delta}.

handle_lashup_gm_mc_event(#{payload := #{type := delta_update} = Payload}, State) ->
  handle_delta_update(Payload, State);
handle_lashup_gm_mc_event(Event = #{payload := #{type := lub_advertise}}, State) ->
  handle_lub_advertise(Event, State);
handle_lashup_gm_mc_event(#{payload := #{type := full_update} = Payload}, State) ->
  handle_full_update(Payload, State);
handle_lashup_gm_mc_event(Payload, State) ->
  lager:debug("Unknown GM MC event: ~p", [Payload]),
  State.

handle_delta_update(_Payload = #{key := Key, vclock := VClock, delta := Delta}, State) ->
  KV = op_getkv(Key),
  %% Does my local vclock descends from the remote one
  %% If so ignore it
  case vclock:descends(KV#kv.vclock, VClock) of
    true ->
      State;
    false ->
      handle_delta_update_write(KV, VClock, Delta),
      State
  end.

handle_delta_update_write(KV = #kv{map = Map, vclock = LocalVClock}, RemoteVClock, Delta) ->
  Map1 = riak_dt_delta_map:merge(Map, Delta),
  VClock1 = vclock:merge([LocalVClock, RemoteVClock]),
  KV1 = KV#kv{map = Map1, vclock = VClock1},
  ets:insert(?MODULE, KV1).

handle_full_update(Payload = #{key := Key, vclock := VClock, map := Map}, State) ->
  KV = op_getkv(Key),
  lager:debug("Full update: ~p", [Payload]),
  Map1 = riak_dt_delta_map:merge(Map, KV#kv.map),
  VClock1 =  vclock:merge([VClock, KV#kv.vclock]),
  KV1 = KV#kv{map = Map1, vclock = VClock1},
  ets:insert(?MODULE, KV1),
  State.


handle_aae_wakeup(State) ->
  MatchSpec = ets:fun2ms(fun(#kv{key = Key, vclock = VClock}) -> {Key, VClock}  end),
  AAEData = ets:select(?MODULE, MatchSpec),
  Payload = #{type => lub_advertise, aae_data => AAEData},
  lashup_gm_mc:multicast(?MODULE, Payload, [{ttl, 1}, {fanout, 1}]),
  State.

%% @private This is an "AAE Event" It is to advertise all of the keys from a given node
handle_lub_advertise(Event = #{origin := Origin, payload := #{aae_data := AAEData}}, State) ->
  sync_missing_keys(Origin, AAEData),
  sync_divergent_keys(Origin, AAEData),
  %% Add vector clock divergence check
  State.

%% This sends the missing keys
sync_missing_keys(Origin, AAEData) ->
  AAEDataSet = orddict:from_list(AAEData),
  KVs =
  qlc:eval(
    qlc:q(
      [KV || KV = #kv{key = Key} <- ets:table(?MODULE), not orddict:is_key(Key, AAEDataSet)]
    )
  ),
  ShuffledList = lashup_utils:shuffle_list(KVs, lashup_utils:seed()),
  TruncatedShuffledList = lists:sublist(ShuffledList, ?MAX_AAE_REPLIES),
  [sync_missing_key(Origin, KV) || KV <- TruncatedShuffledList].

%% TODO: Add backpressure
%% TODO: Add jitter to avoid overwhelming the node we're
sync_missing_key(Origin, _KV = #kv{vclock = VClock, key = Key, map = Map}) ->
  Payload = #{type => full_update, reason => aae, key => Key, map => Map, vclock => VClock},
  SendAfter = trunc(random:uniform() * 10000),
  %% Maybe remove {only_nodes, [Origin]} from MCOpts
  %% to generate more random gossip
  %% The reason ttl = 2 is here is to ensure the update gets back
  MCOpts = [{ttl, 2}, {fanout, 1}, {only_nodes, [Origin]}],
  timer:apply_after(SendAfter, lashup_gm_mc, multicast, [?MODULE, Payload, MCOpts]).

sync_divergent_keys(Origin, AAEData) ->
  AAEKVs =
    qlc:eval(
      qlc:q(
        [{KV, AAEVClock} ||
          KV = #kv{key = Key, vclock = VClock} <- ets:table(?MODULE),
          {AAEKey, AAEVClock} = _AAEKeyData <- AAEData,
          Key == AAEKey andalso VClock =/= AAEVClock andalso not vclock:equal(VClock, AAEVClock)
        ]
      )
    ),
  %% So, we have to be careful here because we can come up with divergence during periods of rapid updates
  %% Although
  [do_sync_divergent_keys(Origin, AAEKV) ||
    AAEKV <- AAEKVs,
    sync_divergent_key_actors(AAEKV) orelse sync_divergent_key_clocks(AAEKV)].

do_sync_divergent_keys(_Origin, AAEKV = {_KV, _RemoteClock}) ->
  lager:debug("Maybe syncing divergence key: ~p", [AAEKV]).

