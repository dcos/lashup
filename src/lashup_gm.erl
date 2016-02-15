%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 15. Jan 2016 2:56 AM
%%%-------------------------------------------------------------------

%% TODO: Get rid of DVVSet, and move to a pruneable datastructure


-module(lashup_gm).
-author("sdhillon").


-behaviour(gen_server).

%% API
-export([start_link/0,
  get_subscriptions/0,
  gm/0,
  get_neighbor_recommendations/1,
  seed/0,
  lookup_node/2,
  id/0
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-include_lib("kernel/include/inet.hrl").
-include_lib("stdlib/include/ms_transform.hrl").
-include_lib("lashup.hrl").

-record(subscriber, {monitor_ref, node, pid}).
-record(subscription, {node, pid, monitor_ref}).
-record(state, {
  subscriptions = [],
  init_time,
  vclock_id,
  seed,
  active_view = [],
  subscribers = []}).

-type state() :: #state{}.

%%%===================================================================
%%% API
%%%===================================================================


%% @doc
%% Timeout here is limited to 500 ms, and not less
%% empirically, dumping 1000 nodes pauses lashup_gm for ~300 ms.
%% So we bumped this up to sit above that. We should decrease it when we get a chance
%% because lashup_hyparview_membership depends on it not pausing for a long time


get_neighbor_recommendations(ActiveViewSize) ->
  gen_server:call(?SERVER, {get_neighbor_recommendations, ActiveViewSize}, 500).

lookup_node(Node, Seed) ->
  case ets:lookup(members, nodekey(Node, Seed)) of
    [] ->
      error;
    [Member] ->
      {ok, Member}
  end.

gm() ->
  get_membership().

get_subscriptions() ->
  gen_server:call(?SERVER, get_subscriptions).

seed() ->
  gen_server:call(?SERVER, seed).

id() ->
  gen_server:call(?SERVER, id).

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
  random:seed(lashup_utils:seed()),
  %% TODO: Add jitter
  MyPid = self(),
  spawn_link(fun() -> update_node_backoff_loop(5000, MyPid) end),
  ets:new(members, [ordered_set, named_table, {keypos, #member.nodekey}, compressed]),
  lashup_hyparview_events:subscribe(
    fun(Event) -> gen_server:cast(?SERVER, #{message => lashup_hyparview_event, event => Event}) end),
  VClockID = {node(), erlang:phash2(random:uniform())},
  State = #state{
    init_time = erlang:monotonic_time(),
    vclock_id = VClockID,
    seed = lashup_utils:seed()
  },
  init_dvvset(State),
  timer:send_interval(3600 * 1000, trim_nodes),
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
handle_call(id, _From, State = #state{vclock_id = VClockID}) ->
  {reply, VClockID, State};
handle_call(gm, _From, State) ->
  {reply, get_membership(), State};
handle_call({subscribe, Pid}, _From, State) ->
  {Reply, State1} = handle_subscribe(Pid, State),
  {reply, Reply, State1};
handle_call(get_subscriptions, _From, State = #state{subscriptions = Subscriptions}) ->
  {reply, Subscriptions, State};
handle_call(update_node, _From, State) ->
  State1 = update_node(State),
  {reply, 300000, State1};
handle_call({get_neighbor_recommendations, ActiveViewSize}, _From, State) ->
  Reply = handle_get_neighbor_recommendations(ActiveViewSize),
  {reply, Reply, State};
handle_call(seed, _From, State = #state{seed = Seed}) ->
  {reply, Seed, State};
handle_call(Request, _From, State) ->
  lager:debug("Received unknown request: ~p", [Request]),
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
handle_cast({compressed, Data}, State) when is_binary(Data) ->
  Data1 = binary_to_term(Data),
  handle_cast(Data1, State);
handle_cast({sync, Pid}, State) ->
  handle_sync(Pid, State),
  {noreply, State};
handle_cast(#{message := remote_event, from := From, event := #{message := updated_node} = UpdatedNode}, State) ->
  %lager:debug("Received Updated Node: ~p", [UpdatedNode]),
  State1 = handle_updated_node(From, UpdatedNode, State),
  {noreply, State1};

handle_cast(#{message := lashup_hyparview_event, event := #{type := current_views} = Event}, State) ->
  State1 = handle_current_views(Event, State),
  {noreply, State1};

handle_cast(update_node, State) ->
  State1 = update_node(State),
  {noreply, State1};

handle_cast(Request, State) ->
  lager:debug("Received unknown cast: ~p", [Request]),
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

handle_info(_Down = {'DOWN', MonitorRef, _Type, _Object, _Info}, State) when is_reference(MonitorRef) ->
  State1 = prune_subscribers(MonitorRef, State),
  State2 = prune_subscriptions(MonitorRef, State1),
  {noreply, State2};

handle_info({nodedown, Node}, State) ->
  State1 = handle_nodedown(Node, State),
  {noreply, State1};
handle_info(trim_nodes, State) ->
  trim_nodes(State),
  {noreply, State};
handle_info(Info, State) ->
  lager:debug("Unknown info: ~p", [Info]),
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
  lager:debug("Lashup_GM terminated, because: ~p, in state: ~p", [Reason, State]),
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

handle_sync(Pid, State) ->
  lashup_gm_sync_worker:handle(Pid, State#state.seed).


-spec(handle_subscribe(Pid :: pid(), State :: state()) -> {{ok, Self :: pid()}, State1 :: state()}).
handle_subscribe(Pid, State = #state{subscribers = Subscribers}) ->
  MonitorRef = monitor(process, Pid),
  Subscriber = #subscriber{node = node(Pid), monitor_ref = MonitorRef, pid = Pid},
  State1 = State#state{subscribers = [Subscriber | Subscribers]},
  {{ok, self()}, State1}.

handle_current_views(_Event = #{active_view := RemoteActiveView}, State = #state{subscriptions = Subscriptions}) ->
  Subscriptions1 = lists:foldl(fun check_member/2, Subscriptions, RemoteActiveView),
  OldActiveView = State#state.active_view,
  case {RemoteActiveView, Subscriptions} of
    {OldActiveView, Subscriptions1} ->
      ok;
    _ ->
      gen_server:cast(self(), update_node)
  end,
  State#state{subscriptions = Subscriptions1, active_view = RemoteActiveView}.


check_member(Node, Subscriptions) ->
  %% Make sure that the node doesn't exist in subscriptions and it's in our connected nodes list
  case {lists:keyfind(Node, #subscription.node, Subscriptions), lists:member(Node, nodes())} of
    {false, true} ->
      %% We should also ensure that the node is up
      case catch lashup_gm_fanout:start_monitor(Node) of
        {ok, {Pid, Monitor}} ->
          Subscription = #subscription{node = Node, pid = Pid, monitor_ref = Monitor},
          lager:debug("Added handler for node: ~p", [Node]),
          [Subscription | Subscriptions];
        Else ->
          lager:debug("Unable to add handler for node: ~p, error: ~p", [Node, Else]),
          Subscriptions
      end;
    _ ->
      Subscriptions
  end.

%% @private Creates a new value for the DVVSet representing node metadata
new_value(NodeClock, _State = #state{active_view = ActiveView, vclock_id = VClockID}) ->
  #{
    active_view => ActiveView,
    server_id => VClockID,
    node_clock => NodeClock
  }.

new_dvvset(NodeClock, State) ->
  dvvset:new(new_value(NodeClock, State)).

update_dvvset(NodeClock, OldDVVSet, State) ->
  DVVSet = dvvset:new(dvvset:join(OldDVVSet), new_value(NodeClock, State)),
  dvvset:update(DVVSet, OldDVVSet, State#state.vclock_id).

%% @private Creates the first Member record representing the local node
init_dvvset(State = #state{vclock_id = VClockID}) ->
  LocalUpdate = NodeClock = erlang:system_time(nano_seconds),
  DVVSet = dvvset:update(new_dvvset(NodeClock, State), VClockID),
  ClockDelta = 0,
  DVVSetValue = lww(DVVSet),
  Member = #member{
    node = node(),
    nodekey = nodekey(node(), State),
    dvvset = DVVSet,
    locally_updated_at = [LocalUpdate],
    clock_deltas = [ClockDelta],
    dvvset_value = DVVSetValue,
    active_view = maps:get(active_view, DVVSetValue)
  },
  persist(Member, State).

nodekey(Node, _State = #state{seed = Seed}) ->
  lashup_utils:nodekey(Node, Seed);
nodekey(Node, Seed) ->
  lashup_utils:nodekey(Node, Seed).

%% @private Update the local node's DVVSet
update_node(State) ->
  [Member] = ets:lookup(members, nodekey(node(), State)),
  NodeClock = erlang:system_time(nano_seconds),
  MergedDVVSet = update_dvvset(NodeClock, Member#member.dvvset, State),
  update_node(MergedDVVSet, State).

%% @private Take an updated DVVSet from the local node, turn it into a message and propagate it
update_node(NewDVVSet, State) ->
  %% TODO:
  %% Adjust TTL based on maximum path length from link-state database
  Message = #{
    message => updated_node,
    node => node(),
    ttl => 10,
    dvvset => NewDVVSet
  },
  handle_updated_node(node(), Message, State).

handle_updated_node(_From, UpdatedNode = #{ttl := TTL}, State) when TTL < 0 ->
  lager:warning("TTL Exceeded on Updated Node: ~p", [UpdatedNode]),
  State;

handle_updated_node(From, UpdatedNode = #{node := Node}, State) ->
  case ets:lookup(members, nodekey(Node, State)) of
    [] ->
      %% Brand new, store it
      store_and_forward_new_updated_node(From, UpdatedNode, State);
    [Member] ->
      maybe_store_store_and_forward_updated_node(Member, From, UpdatedNode, State)
  end.

%% @private Take a new node we've never seen before, and store it in the membership database
store_and_forward_new_updated_node(From,
  UpdatedNode = #{
    node := Node,
    ttl := TTL,
    dvvset := DVVSet
  }, State) ->
  LocalUpdate = erlang:monotonic_time(nano_seconds),
  DVVSetValue = lww(DVVSet),
  NodeClock = maps:get(node_clock, DVVSetValue),
  ClockDelta = abs(NodeClock - LocalUpdate),
  Member = #member{
    node = Node,
    nodekey = nodekey(Node, State),
    locally_updated_at = [LocalUpdate],
    clock_deltas = [ClockDelta],
    dvvset = DVVSet,
    dvvset_value = DVVSetValue,
    active_view = maps:get(active_view, DVVSetValue)
  },
  persist(Member, State),
  NewUpdatedNode = UpdatedNode#{exempt_nodes => [From], ttl => TTL - 1},
  forward(NewUpdatedNode, State),
  State.


maybe_store_store_and_forward_updated_node(Member, From, UpdatedNode = #{dvvset := DVVSet}, State) ->
  %% Should be true, if the remote one is newer
  RemoteVector = dvvset:join(DVVSet),
  LocalVector = dvvset:join(Member#member.dvvset),
  case {dvvset:descends(RemoteVector, LocalVector), dvvset:descends(LocalVector, RemoteVector)} of
    %% The two are equal
    {true, true} ->
      ok;
    %% Our local vector is newer
    {false, true} ->
      ok;
    {true, false} ->
      store_and_forward_updated_node(Member, From, UpdatedNode, State);
    %% We've experienced a concurrency event
    {false, false} ->
      merge_and_forward_updated_node(Member, From, UpdatedNode, State)
  end,
  State.

store_and_forward_updated_node(Member, From, _UpdatedNode, _State)
    when Member#member.node == node() andalso From =/= node() ->
  ok;
store_and_forward_updated_node(Member, From,
  UpdatedNode = #{
    dvvset := DVVSet
  }, State)  ->
  OldDVVSet = Member#member.dvvset,
  NewDVVSet = dvvset:sync([DVVSet, OldDVVSet]),
  update_local_member(NewDVVSet, Member, State),
  NewUpdatedNode = UpdatedNode#{exempt_nodes => [From]},
  forward(NewUpdatedNode, State);
store_and_forward_updated_node(_Member, _From, _UpdatedNode, _State) ->
  ok.

%% Recirculate the update, infusing it with more information, and updating the clock
merge_and_forward_updated_node(Member, _From, _UpdatedNode = #{dvvset := DVVSet, node := Node}, State)
    when Node == node()->
  lager:debug("Received greater clock about self from network: ~p, local: ~p", [DVVSet, Member#member.dvvset]),
  %% Sync the remote DVVSet and our local one
  NewDVVSet = dvvset:sync([DVVSet, Member#member.dvvset]),
  Timestamp = erlang:system_time(nano_seconds),
  MergedDVVSet = update_dvvset(Timestamp, NewDVVSet, State),
  update_node(MergedDVVSet, State);
%% Sync the two values, but do not alter them
merge_and_forward_updated_node(Member, From, UpdatedNode = #{dvvset := DVVSet}, State) ->
  NewDVVSet = dvvset:sync([DVVSet, Member#member.dvvset]),
  NewUpdatedNode = UpdatedNode#{
    dvvset => NewDVVSet,
    exempt_nodes => [From]
  },
  update_local_member(NewDVVSet, Member, State),
  forward(NewUpdatedNode, State).

%% @doc update a local member, and persist it to ets, from a DVVSet
%% The DVVSet has to already be merged from the one we got off the network
update_local_member(DVVSet, Member, State) ->
  Now = erlang:monotonic_time(nano_seconds),
  NewDVVSetValue = lww(DVVSet),
  NodeClock = maps:get(node_clock, NewDVVSetValue),
  NewLocallyUpdatedAt = lists:sublist([Now | Member#member.locally_updated_at], 100),
  ClockDelta = abs(NodeClock - Now),
  NewClockDelta = lists:sublist([ClockDelta | Member#member.clock_deltas], 100),
  NewMember = Member#member{
    locally_updated_at = NewLocallyUpdatedAt,
    clock_deltas = NewClockDelta,
    dvvset = DVVSet,
    dvvset_value = NewDVVSetValue,
    active_view = maps:get(active_view, NewDVVSetValue)
  },
  process_new_member(Member, NewMember, State),
  persist(NewMember, State).


forward(_NewUpdatedNode = #{ttl := TTL}, _State) when TTL =< 0 ->
  ok;
forward(NewUpdatedNode = #{ttl := TTL}, _State = #state{subscribers = Subscribers}) ->
  NewUpdatedNode1 = NewUpdatedNode#{ttl := TTL - 1},
  CompressedTerm = term_to_binary(NewUpdatedNode1, [compressed]),
  Fun =
    fun(_Subscriber = #subscriber{pid = Pid}) ->
      erlang:send(Pid, {event, CompressedTerm}, [noconnect])
    end,
  lists:foreach(Fun, Subscribers).


handle_nodedown(Node, State = #state{subscriptions = Subscriptions, subscribers = Subscribers}) ->
  lager:debug("Removing subscription (nodedown) from node: ~p", [Node]),
  Subscriptions1 = lists:keydelete(Node, #subscription.node, Subscriptions),
  Subscribers1 = lists:keydelete(Node, #subscriber.node, Subscribers),
  State#state{subscriptions = Subscriptions1, subscribers = Subscribers1}.

get_membership() ->
  ets:foldl(fun accumulate_membership/2, [], members).


accumulate_membership(Member, Acc) ->
  Now = erlang:monotonic_time(),
  [LastHeard | _] = Member#member.locally_updated_at,
  TimeSinceLastHeard = erlang:convert_time_unit(Now - LastHeard, native, milli_seconds),
  Node = #{
    node => Member#member.node,
    time_since_last_heard => TimeSinceLastHeard,
    active_view => Member#member.active_view
  },
  [Node | Acc].

trim_nodes(State) ->
  Now = erlang:monotonic_time(),
  Delta = erlang:convert_time_unit(86400, seconds, native),
  MatchSpec = ets:fun2ms(
    fun(Member = #member{locally_updated_at = LocallyUpdatedAt})
      when Now - hd(LocallyUpdatedAt) > Delta andalso Member#member.node =/= node()
      -> Member
    end
  ),
  Members = ets:select(members, MatchSpec),
  lists:foreach(fun(X) -> delete(X, State) end, Members).

update_node_backoff_loop(Delay, Pid) ->
  timer:sleep(Delay),
  Backoff = gen_server:call(?SERVER, update_node, infinity),
  update_node_backoff_loop(Backoff, Pid).

prune_subscribers(MonitorRef, State = #state{subscribers = Subscribers}) ->
  Subscribers1 = lists:keydelete(MonitorRef, #subscriber.monitor_ref, Subscribers),
  State#state{subscribers = Subscribers1}.

prune_subscriptions(MonitorRef, State = #state{subscriptions = Subscription}) ->
  Subscription1 = lists:keydelete(MonitorRef, #subscription.monitor_ref, Subscription),
  State#state{subscriptions = Subscription1}.


%% @doc
%% This function (at the moment) only triggers for the purposes to hint back to hyparview membership
%% for aggressive probes
%% Effectively, it means that we have observed another node evict one of our active neighbors from its active set
%% Therefore, we are going to check if it's a dirty liar, or not.
%% it's less new member, but more a change in another member

%% @end
-spec(process_new_member(MemberOld :: member(), MemberNew :: member(), State :: state()) -> ok).
process_new_member(Member, NewMember, _State = #state{active_view = HyparViewActiveView}) ->
  ActiveView1 = Member#member.active_view,
  ActiveView2 = NewMember#member.active_view,
  ActiveView1Set = ordsets:from_list(ActiveView1),
  ActiveView2Set = ordsets:from_list(ActiveView2),
  RetiredMembersSet = ordsets:subtract(ActiveView1Set, ActiveView2Set),
  HyparViewActiveViewSet = ordsets:from_list(HyparViewActiveView),
  ProbeNodes = ordsets:intersection(RetiredMembersSet, HyparViewActiveViewSet),
  [lashup_hyparview_ping_handler:ping(ProbeNode) || ProbeNode <- ProbeNodes],
  ok.

handle_get_neighbor_recommendations(ActiveViewSize) ->
  %% We don't have to do any randomization on the table to avoid colliding joins
  %% the reason for this is that every row is prefixed with the nodekey
  %% and the nodekey is generated based on a hash of the node
  %% and a locally generated nonce
  %% So, everyone will have a slightly different sort order
  MatchSpec = ets:fun2ms(
    fun(Member = #member{active_view = ActiveView})
      when length(ActiveView) < ActiveViewSize andalso Member#member.node =/= node()
      -> Member
    end
  ),
  case ets:select(members, MatchSpec, 1) of
    {[Member], _Continuation} ->
      {ok, Member#member.node};
    '$end_of_table' ->
      false
  end.

%% ETS write functions
delete(Member = #member{}, _State) ->
  lashup_gm_route:delete_node(Member#member.node),
  case ets:lookup(members, Member#member.nodekey) of
    [Member] ->
      ets:delete(members, Member#member.nodekey),
      ok;
    [] ->
      ok
  end.


%% TODO:
%% Rewrite both
-spec(persist(Member :: member(), State :: state()) -> ok).
persist(Member, _State) ->
  lashup_gm_route:update_node(Member#member.node, Member#member.active_view),
  case ets:lookup(members, Member#member.nodekey) of
    [OldMember] ->
      ets:insert(members, Member),
      lashup_gm_events:ingest(OldMember, Member);
    [] ->
      ets:insert(members, Member),
      lashup_gm_events:ingest(Member)
  end,
  %% Find the component I'm part of
  ok.

lww_value(_Value1 = #{node_clock := NodeClock1}, _Value2 = #{node_clock := NodeClock2}) ->
  NodeClock1 =< NodeClock2.


%% Add reconilation code
lww(DVVSet) ->
  LWW = dvvset:lww(fun lww_value/2, DVVSet),
  [Value] = dvvset:values(LWW),
  Value.

