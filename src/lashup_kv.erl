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

-export_type([key/0]).

-define(SERVER, ?MODULE).
-define(MAX_AAE_REPLIES, 10).
%% What's the maximum number of lubs to advertise
-define(AAE_LUB_LIMIT, 100).

-define(WARN_OBJECT_SIZE_KB, 25).
-define(REJECT_OBJECT_SIZE_KB, 100).


-type actor_id() :: {Node :: node(), Uid :: integer()}.
-record(state, {
  mc_ref = erlang:error() :: reference(),
  actor_id = erlang:error() :: actor_id(),
  metadata_snapshot_current = [] :: metadata_snapshot(),
  metadata_snapshot_next = [] :: metadata_snapshot(),
  last_selected_key = '$end_of_table' :: '$end_of_table' | key()
}).


-type metadata_snapshot() :: [{key(), vclock:vclock()}].

-include("lashup_kv.hrl").
-type keys() :: [key()].

-type kv() :: #kv{}.
-type state() :: #state{}.
-type aae_data() :: orddict:orddict(key(), vclock:vclock()).


%%%===================================================================
%%% API
%%%===================================================================

-spec(request_op(Key :: key(), Op :: riak_dt_map:map_op()) ->
  {ok, riak_dt_map:value()} | {error, Reason :: term()}).
request_op(Key, Op) ->
  gen_server:call(?SERVER, {op, Key, Op}).

-spec(value(Key :: key()) -> riak_dt_map:value()).
value(Key) ->
  {_, KV} = op_getkv(Key),
  riak_dt_map:value(KV#kv.map).

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
  %% 1-2 minute jitter time for doing AAE, but the first 10 ticks are compressed
  lashup_timers:wakeup_loop(aae_wakeup,
    lashup_timers:wait(60000,
      lashup_timers:linear_ramp_up(10,
        lashup_timers:jitter_uniform(
          fun lashup_config:aae_interval/0
        )))),

  %% Take snapshots faster in the beginning than in running state, then every 10s
  lashup_timers:wakeup_loop(metadata_snapshot,
    lashup_timers:jitter_uniform(
      lashup_timers:linear_ramp_up(10,
          10000
    ))),

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
  {Reply, State1} = handle_op(Key, Op, State),
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

-spec handle_op(Key :: term(), Op :: riak_dt_map:map_op(), State :: state()) -> {Reply :: term(), State1 :: state()}.
handle_op(Key, Op, State) ->
  {NewOrExisting, KV} = op_getkv(Key),
  case modify_map(KV, Op, State) of
    {ok, NewKV} ->
      %% Do stuff
      propagate(NewKV),
      persist(NewOrExisting, KV, NewKV),
      NewValue = riak_dt_map:value(NewKV#kv.map),
      {{ok, NewValue}, State};
    Error = {error, _Reason} ->
      {Error, State}
      %% Don't do stuff
  end.


-spec(modify_map(KV :: kv(), Op :: riak_dt_map:map_op(), State :: state()) ->
{ok, KV1 :: kv(), Map :: riak_dt_map:dt_map()} | {error, Reason :: term()}).
modify_map(KV = #kv{vclock = VClock, map = Map}, Op, _State = #state{actor_id = ActorID}) ->
  Now = erlang:system_time(nano_seconds),
  VClock1 = vclock:increment(ActorID, Now, VClock),
  {ok, ImpureDot} = vclock:get_dot(ActorID, VClock1),
  Dot = vclock:pure_dot(ImpureDot),
  {ok, Map1} = riak_dt_map:update(Op, Dot, Map),
  KV1 = KV#kv{vclock = VClock1, map = Map1},
  case check_map(KV1) of
    ok ->
      {ok, KV1};
    Error = {error, _Reason} ->
      Error
  end.



%% TODO: Add metrics
-spec(check_map(kv()) -> {error, Reason :: term()} | ok).
check_map(NewKV = #kv{key = Key}) ->
  case erlang:external_size(NewKV) of
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
  Payload = #{type => full_update, reason => aae, key => Key, map => Map, vclock => VClock},
  lashup_gm_mc:multicast(?MODULE, Payload),
  ok.

% @private either gets the KV object for a given key, or returns an empty one
-spec(op_getkv(key()) -> {new, kv()} | {existing, kv()}).
op_getkv(Key) ->
  case ets:lookup(?MODULE, Key) of
    [] ->
      {new, #kv{key = Key}};
    [KV] ->
      {existing, KV}
  end.

-spec(persist(new | existing, kv(), kv()) -> ok).
persist(new, _OldKV, KV = #kv{key = Key, vclock = VClock, map = Map}) ->
  true = ets:insert(?MODULE, KV),
  lashup_kv_events:ingest(Key, Map, VClock),
  ok;
persist(existing, OldKV, KV = #kv{key = Key, vclock = VClock, map = Map}) ->
  true = ets:insert(?MODULE, KV),
  lashup_kv_events:ingest(Key, OldKV#kv.map, Map, VClock),
  ok.


-spec(handle_lashup_gm_mc_event(map(), state()) -> state()).
handle_lashup_gm_mc_event(Event = #{payload := #{type := lub_advertise}}, State) ->
  handle_lub_advertise(Event, State);
handle_lashup_gm_mc_event(#{payload := #{type := full_update} = Payload}, State) ->
  handle_full_update(Payload, State);
handle_lashup_gm_mc_event(Payload, State) ->
  lager:debug("Unknown GM MC event: ~p", [Payload]),
  State.

-spec(handle_full_update(map(), state()) -> state()).
handle_full_update(_Payload = #{key := Key, vclock := VClock, map := Map}, State) ->
  {NewOrExisting, KV} = op_getkv(Key),
  case get_maybe_write(KV, Map, VClock) of
    {ok, NewKV} ->
      persist(NewOrExisting, KV, NewKV);
    false ->
      ok
  end,
  State.

-spec(get_maybe_write(kv(), riak_dt_map:dt_map(), vclock:vclock()) -> false | {ok, kv()}).
get_maybe_write(KV = #kv{vclock = LocalVClock}, RemoteMap, RemoteVClock) ->
  case {vclock:descends(RemoteVClock, LocalVClock), vclock:descends(LocalVClock, RemoteVClock)} of
    {true, false} ->
      get_write(KV, RemoteMap, RemoteVClock);
    {false, false} ->
      get_write(KV, RemoteMap, RemoteVClock);
    %% Either they are equal, or the local one is newer - perhaps trigger AAE?
    _ ->
      false
  end.

-spec(get_write(kv(), riak_dt_map:dt_map(), vclock:vclock()) -> {ok, kv()}).
get_write(KV = #kv{vclock = LocalVClock}, RemoteMap, RemoteVClock) ->
  Map1 = riak_dt_map:merge(RemoteMap, KV#kv.map),
  VClock1 = vclock:merge([LocalVClock, RemoteVClock]),
  KV1 = KV#kv{map = Map1, vclock = VClock1},
  {ok, KV1}.


-spec(aae_snapshot() -> aae_data()).
aae_snapshot() ->
  MatchSpec = ets:fun2ms(fun(#kv{key = Key, vclock = VClock}) -> {Key, VClock}  end),
  KeyClocks = ets:select(?MODULE, MatchSpec),
  orddict:from_list(KeyClocks).


% @doc This is the function that gets called to begin the AAE process

%% We send out a set of all our {key, VClock} pairs
-spec(handle_aae_wakeup(state()) -> state()).
handle_aae_wakeup(State) ->
  aae_controlled_snapshot([State#state.last_selected_key], State).

%% We have more than ?AAE_LUB_LIMIT keys
-spec(aae_controlled_snapshot([key() | '$end_of_table'], state()) -> state()).
aae_controlled_snapshot(Acc, State) when length(Acc) >= ?AAE_LUB_LIMIT  ->
  aae_begin_end(Acc, State);
%% The table is empty
aae_controlled_snapshot(['$end_of_table', '$end_of_table'], State) ->
  aae_begin_end([], State);
%% We're having to reset to the beginning of the table - because the first key that was put in there was end of table
aae_controlled_snapshot(Acc = ['$end_of_table'], State) ->
  Key = ets:first(?MODULE),
  aae_controlled_snapshot([Key|Acc], State#state{last_selected_key = Key});
%% We've hit the end of the table
aae_controlled_snapshot(Acc = ['$end_of_table'| _RestKeys], State) ->
  aae_begin_end(Acc, State);
%% We're still traversing the table
aae_controlled_snapshot(Acc = [PreviousKey|_], State) ->
  Key = ets:next(?MODULE, PreviousKey),
  aae_controlled_snapshot([Key|Acc], State#state{last_selected_key = Key}).

%% Empty table
-spec(aae_begin_end(keys(), state()) -> state()).
aae_begin_end([], State) ->
  aae_advertise_data(#{aae_data => []}, State);
aae_begin_end(['$end_of_table'], State) ->
  aae_advertise_data(#{aae_data => []}, State);
aae_begin_end(Keys = [LastKey|_RestKeys], State) ->
  [FirstKey|_] = SortedKeys = lists:reverse(Keys),
  Records = [{Key, ets:lookup_element(?MODULE, Key, #kv.vclock)} || Key <- SortedKeys, Key =/= '$end_of_table'],
  aae_begin_end(FirstKey, LastKey, Records, State).

%% We iterated through the entire table
-spec(aae_begin_end(key(), key(), [{key(), kv()}], state()) -> state()).
aae_begin_end('$end_of_table', '$end_of_table', Records, State = #state{last_selected_key = '$end_of_table'}) ->
  aae_advertise_data(#{aae_data => Records}, State);

%% We started at the beginning of the table, and got to the middle
aae_begin_end('$end_of_table', LastKey, Records, State) ->
  aae_advertise_data(#{aae_data => Records, end_key => LastKey}, State);

%% We started in the middle and ended at the end
aae_begin_end(FirstKey, '$end_of_table', Records, State) ->
  aae_advertise_data(#{aae_data => Records, start_key => FirstKey}, State);

%% We started in the middle and ended at the middle
aae_begin_end(FirstKey, LastKey, Records, State) ->
  aae_advertise_data(#{aae_data => Records, start_key => FirstKey, end_key => LastKey}, State).

-spec(aae_advertise_data(map(), state()) -> state()).
aae_advertise_data(Payload, State) ->
  Payload1 = Payload#{type => lub_advertise},
  lashup_gm_mc:multicast(?MODULE, Payload1, [{ttl, 1}, {fanout, 1}]),
  State.

%% The metrics snapshot is empty. We will skip this round of responding to AAE.
-spec(handle_lub_advertise(map(), state()) -> state()).
handle_lub_advertise(_Event, State = #state{metadata_snapshot_current = []}) ->
  State;
handle_lub_advertise(#{origin := Origin, payload := #{aae_data := RemoteAAEData} = Payload},
    State = #state{metadata_snapshot_current = LocalAAEData}) ->
  LocalAAEData1 = trim_local_aae_data(LocalAAEData, Payload),
  sync(Origin, LocalAAEData1, RemoteAAEData),
  %% Add vector clock divergence check
  State.

-spec(trim_local_aae_data(aae_data(), map()) -> aae_data()).
trim_local_aae_data(LocalAAEData, #{start_key := StartKey, end_key := EndKey}) ->
  [Entry || Entry = {Key, _} <- LocalAAEData,
    Key >= StartKey,
    Key =< EndKey];
trim_local_aae_data(LocalAAEData, #{start_key := StartKey}) ->
  [Entry || Entry = {Key, _} <- LocalAAEData,
    Key >= StartKey];
trim_local_aae_data(LocalAAEData, #{end_key := EndKey}) ->
  [Entry || Entry = {Key, _} <- LocalAAEData,
    Key =< EndKey];
trim_local_aae_data(LocalAAEData, _) ->
  LocalAAEData.

-spec(sync(node(), aae_data(), aae_data()) -> ok).
sync(Origin, LocalAAEData, RemoteAAEData) ->
  %% Prioritize merging MissingKeys over Divergent Keys.
  Keys = keys_to_sync(LocalAAEData, RemoteAAEData),
  sync_keys(Origin, Keys).

-spec(sync_keys(Origin :: node(), keys()) -> ok).
sync_keys(Origin, KeyList) ->
  KVs = [op_getkv(Key) || Key <- KeyList],
  KVs1 = [KV || {_, KV} <- KVs],
  [sync_key(Origin, KV) || KV <- KVs1],
  ok.

-spec(keys_to_sync(aae_data(), aae_data()) -> keys()).
keys_to_sync(LocalAAEData, RemoteAAEData) ->
  MissingKeys = missing_keys(LocalAAEData, RemoteAAEData),
  keys_to_sync(MissingKeys, LocalAAEData, RemoteAAEData).

-spec(keys_to_sync(keys(), aae_data(), aae_data()) -> keys()).
keys_to_sync(MissingKeys, _LocalAAEData, _RemoteAAEData)
    when length(MissingKeys) > ?MAX_AAE_REPLIES ->
  MissingKeys;
keys_to_sync(MissingKeys, LocalAAEData, RemoteAAEData) ->
  DivergentKeys = divergent_keys(LocalAAEData, RemoteAAEData),
  Keys = ordsets:union(MissingKeys, DivergentKeys),
  keys_to_sync(Keys).

-spec(keys_to_sync(keys()) -> keys()).
keys_to_sync(Keys) ->
  Shuffled = lashup_utils:shuffle_list(Keys),
  lists:sublist(Shuffled, ?MAX_AAE_REPLIES).


%% TODO: Add backpressure
-spec(sync_key(Origin :: node(), KV :: kv()) -> ok).
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
  timer:apply_after(SendAfter, lashup_gm_mc, multicast, [?MODULE, Payload, MCOpts]),
  ok.


%% @private Finds the missing keys from remote metadata snapshot
-spec(missing_keys(LocalAAEData :: metadata_snapshot(), RemoteAAEData :: metadata_snapshot()) -> [key()]).
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


%% @private Given two metadata snapshots, it returns which keys diverge (have concurrent changes)
-spec(divergent_keys(LocalAAEData :: metadata_snapshot(), RemoteAAEData :: metadata_snapshot()) -> [key()]).
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

%% @private promotes the next snapshot, to th current metadata snapshot, and takes the next snapshot
%% May make sense to build the snapshot asynchronously
-spec(handle_metadata_snapshot(state()) -> state()).
handle_metadata_snapshot(State = #state{metadata_snapshot_next = MSN}) ->
  State#state{metadata_snapshot_current = MSN, metadata_snapshot_next = aae_snapshot()}.
