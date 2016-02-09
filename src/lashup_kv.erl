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
  actor_id = erlang:error() :: actor_id(),
  metadata_snapshot_current = [] :: metadata_snapshot(),
  metadata_snapshot_next = [] :: metadata_snapshot()
}).


-type metadata_snapshot() :: [{key(), vclock:vclock()}].

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
  rand:seed(exs1024),
  ResolverConfig =
    lashup_timers:wait(60000,
      lashup_timers:linear_ramp_up(10,
        lashup_timers:jitter_uniform(
          fun lashup_config:aae_interval/0
        ))),

  lashup_timers:wakeup_loop(aae_wakeup, ResolverConfig),

  lashup_timers:wakeup_loop(metadata_snapshot,
    lashup_timers:jitter_uniform(
      lashup_timers:linear_ramp_up(10,
        lashup_timers:jitter_uniform(
          10000
    )))),

  %% Maybe read_concurrency?
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
handle_info(metadata_snapshot, State) ->
  State1 = handle_metadata_snapshot(State),
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

%% TODO: Add metrics
chk_op(OpStatus = {ok, NewKV = #kv{key = Key}, _Delta}, State) ->
  case erlang:external_size(NewKV) of
    Size when Size > ?REJECT_OBJECT_SIZE_KB * 10000 ->
      {{error, value_too_large}, State};
    Size when Size > (?WARN_OBJECT_SIZE_KB + ?REJECT_OBJECT_SIZE_KB) / 2 * 10000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes (REJECTION IMMINENT)", [Key, Size]),
      commit_op(OpStatus, State);
    Size when Size > ?WARN_OBJECT_SIZE_KB * 10000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes", [Key, Size]),
      commit_op(OpStatus, State);
    _ ->
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

handle_full_update(_Payload = #{key := Key, vclock := VClock, map := Map}, State) ->
  KV = op_getkv(Key),
  Map1 = riak_dt_delta_map:merge(Map, KV#kv.map),
  VClock1 =  vclock:merge([VClock, KV#kv.vclock]),
  KV1 = KV#kv{map = Map1, vclock = VClock1},
  ets:insert(?MODULE, KV1),
  State.

aae_snapshot() ->
  MatchSpec = ets:fun2ms(fun(#kv{key = Key, vclock = VClock}) -> {Key, VClock}  end),
  KeyClocks = ets:select(?MODULE, MatchSpec),
  orddict:from_list(KeyClocks).

% @doc This is the function that gets called to begin the AAE process

%% We send out a set of all our {key, VClock} pairs
handle_aae_wakeup(State) ->
  lager:debug("Beginning AAE LUB announcement"),
  AAEData = aae_snapshot(),
  Payload = #{type => lub_advertise, aae_data => AAEData},
  lashup_gm_mc:multicast(?MODULE, Payload, [{ttl, 1}, {fanout, 1}]),
  State.

%% @private This is an "AAE Event" It is to advertise all of the keys from a given node

%% The metrics snapshot is empty. We will skip this round of responding to AAE.
handle_lub_advertise(_Event, State = #state{metadata_snapshot_current = []}) ->
  State;
handle_lub_advertise(_Event = #{origin := Origin, payload := #{aae_data := RemoteAAEData}},
    State = #state{metadata_snapshot_current = LocalAAEData}) ->
  sync(Origin, LocalAAEData, RemoteAAEData),
  %% Add vector clock divergence check
  State.

sync(Origin, LocalAAEData, RemoteAAEData) ->
  %% Prioritize merging MissingKeys over Divergent Keys.
  lager:debug("Beginning AAE Sync local: ~p <~~~~~~~~~~~~~~> ~p", [maps:from_list(LocalAAEData), maps:from_list(RemoteAAEData)]),
  Keys = keys_to_sync(LocalAAEData, RemoteAAEData),
  lager:debug("Syncing keys: ~p", [Keys]),
  sync_keys(Origin, Keys).

sync_keys(Origin, KeyList) ->
  KVs = [op_getkv(Key) || Key <- KeyList],
  [sync_key(Origin, KV) || KV <- KVs].

keys_to_sync(LocalAAEData, RemoteAAEData) ->
  MissingKeys = missing_keys(LocalAAEData, RemoteAAEData),
  lager:debug("Adding missing keys to sync: ~p", [MissingKeys]),
  keys_to_sync(MissingKeys, LocalAAEData, RemoteAAEData).

keys_to_sync(MissingKeys, _LocalAAEData, _RemoteAAEData)
    when length(MissingKeys) > ?MAX_AAE_REPLIES ->
  MissingKeys;
keys_to_sync(MissingKeys, LocalAAEData, RemoteAAEData) ->
  DivergentKeys = divergent_keys(LocalAAEData, RemoteAAEData),
  lager:debug("Adding divergent keys to sync: ~p", [DivergentKeys]),
  Keys = ordsets:union(MissingKeys, DivergentKeys),
  keys_to_sync(Keys).

keys_to_sync(Keys) ->
  Shuffled = lashup_utils:shuffle_list(Keys),
  lists:sublist(Shuffled, ?MAX_AAE_REPLIES).


%% TODO: Add backpressure
%% TODO: Add jitter to avoid overwhelming the node we're
sync_key(_Origin, _KV = #kv{vclock = VClock, key = Key, map = Map}) ->
  Payload = #{type => full_update, reason => aae, key => Key, map => Map, vclock => VClock},
  SendAfter = trunc(rand:uniform() * 10000),
  %% Maybe remove {only_nodes, [Origin]} from MCOpts
  %% to generate more random gossip
  %% Think about adding: {only_nodes, [Origin]}

  %% So, it's likely that this update will go the 6 nodes near me.
  %% They can then AAE across the cluster.
  %% Given this, "convergence" is the period time * the diameter of the network
  %% We've setup the network to have diameters of <10. The default AAE timeout is 5-10 minutes
  %% So, convergence is about ~1 hour for the K/V store assuming worst case scenario

  %% One of the ideas is to allow the LUB advertisements to fan out throughout the network.
  %% Catching up can be done optimistically (I received a new version of this object via AAE)
  %% and I think my neighbor hasn't seen it because of the last advertisement.
  %% Allowing this to cascade throughout. But systems that cascade uncontrollably
  %% are complicated and prone to failure

  %% Another idea is to use the routing database to elect a root for the network
  %% The leader doesn't need to be strongly consistent, just weakly, and we can
  %% send LUB announcements to that node, and have it deal with global AAE
  %% -Sargun Dhillon
  %% 2/9/2016

  MCOpts = [{ttl, 1}, {fanout, 1}],
  timer:apply_after(SendAfter, lashup_gm_mc, multicast, [?MODULE, Payload, MCOpts]).


%% This finds the missing keys from the remote data
missing_keys(LocalAAEData, RemoteAAEData) ->
  RemoteAAEDataDict = orddict:from_list(RemoteAAEData),
  LocalAAEDataDict = orddict:from_list(LocalAAEData),
  RemoteAAEDataSet = ordsets:from_list(orddict:fetch_keys(RemoteAAEDataDict)),
  LocalAAEDataSet = ordsets:from_list(orddict:fetch_keys(LocalAAEDataDict)),
  ordsets:subtract(LocalAAEDataSet, RemoteAAEDataSet).

%% The logic goes here:
%% 1. We must be comparing the same key
%% 2. The literal erlang datastructures for the clocks must not be the same
%% 3. The logical datastructures must not be equivalent
%% 3a. If I descend from the remote vector clock, I win orelse
%% 3b. If the remote vector clock does not descend from me, I win (concurrency)


%% descends(A, B) andalso not descends(B, A).
divergent_keys(LocalAAEData, RemoteAAEData) ->
  [ LocalKey ||
    {LocalKey, LocalClock} <- LocalAAEData,
    {RemoteKey, RemoteClock} <- RemoteAAEData,
    LocalKey == RemoteKey,
    LocalClock =/= RemoteClock
      andalso (not vclock:equal(LocalClock, RemoteClock))
      andalso (
        vclock:descends(LocalClock, RemoteClock) orelse
        not vclock:descends(RemoteClock, LocalClock)
      )
    ].

handle_metadata_snapshot(State = #state{metadata_snapshot_next = MSN}) ->
  State#state{metadata_snapshot_current = MSN, metadata_snapshot_next = aae_snapshot()}.
