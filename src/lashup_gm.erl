-module(lashup_gm).
-author("sdhillon").
-behaviour(gen_server).

-include_lib("kernel/include/inet.hrl").
-include_lib("stdlib/include/ms_transform.hrl").
-include("lashup.hrl").

%% API
-export([
  start_link/0,
  get_subscriptions/0,
  gm/0,
  get_neighbor_recommendations/1,
  lookup_node/1,
  id/0,
  id/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
  handle_info/2, terminate/2, code_change/3]).

-record(subscriber, {
    monitor_ref,
    node,
    pid
}).

-record(subscription, {
    node,
    pid,
    monitor_ref
}).

-record(state, {
  subscriptions = [],
  epoch = erlang:error() :: non_neg_integer(),
  active_view = [],
  subscribers = [],
  hyparview_event_ref :: reference()
}).

-type state() :: #state{}.

%% @doc
%% TODO: Get rid of DVVSet, and move to a pruneable datastructure
%% Timeout here is limited to 500 ms, and not less
%% empirically, dumping 1000 nodes pauses lashup_gm for ~300 ms.
%% So we bumped this up to sit above that. We should decrease it when we get a chance
%% because lashup_hyparview_membership depends on it not pausing for a long time

get_neighbor_recommendations(ActiveViewSize) ->
  gen_server:call(?MODULE, {get_neighbor_recommendations, ActiveViewSize}, 500).

%% @doc Looks up a node in ets
lookup_node(Node) ->
  case ets:lookup(members, Node) of
    [] ->
      error;
    [Member] ->
      {ok, Member}
  end.

gm() ->
  get_membership().

get_subscriptions() ->
  gen_server:call(?MODULE, get_subscriptions).

id() ->
  node().

id(Node) ->
  Node.


-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  rand:seed(exsplus),
  %% TODO: Add jitter
  MyPid = self(),
  spawn_link(fun() -> update_node_backoff_loop(5000, MyPid) end),
  ets:new(members, [ordered_set, named_table, {keypos, #member2.node}]),
  {ok, HyparviewEventsRef} = lashup_hyparview_events:subscribe(),
  State = #state{epoch = new_epoch(), hyparview_event_ref = HyparviewEventsRef},
  init_node(State),
  timer:send_interval(3600 * 1000, trim_nodes),
  {ok, State}.

handle_call(gm, _From, State) ->
  {reply, get_membership(), State};
handle_call({subscribe, Pid}, _From, State) ->
  {Reply, State1} = handle_subscribe(Pid, State),
  {reply, Reply, State1};
handle_call(get_subscriptions, _From, State = #state{subscriptions = Subscriptions}) ->
  {reply, Subscriptions, State};
handle_call(update_node, _From, State) ->
  State1 = update_node(timed_refresh, State),
  {reply, 300000, State1};
handle_call({get_neighbor_recommendations, ActiveViewSize}, _From, State) ->
  Reply = handle_get_neighbor_recommendations(ActiveViewSize),
  {reply, Reply, State};
handle_call(Request, _From, State) ->
  lager:debug("Received unknown request: ~p", [Request]),
  {reply, ok, State}.

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
handle_cast(update_node, State) ->
  State1 = update_node(internal_cast, State),
  {noreply, State1};

handle_cast(Request, State) ->
  lager:debug("Received unknown cast: ~p", [Request]),
  {noreply, State}.

handle_info(_Down = {'DOWN', MonitorRef, _Type, _Object, _Info}, State) when is_reference(MonitorRef) ->
  State1 = prune_subscribers(MonitorRef, State),
  State2 = prune_subscriptions(MonitorRef, State1),
  {noreply, State2};
handle_info({lashup_hyparview_events, #{type := current_views, ref := EventRef, active_view := ActiveView}},
  State0 = #state{hyparview_event_ref = EventRef}) ->
  State1 = handle_current_views(ActiveView, State0),
  {noreply, State1};
handle_info({nodedown, Node}, State) ->
  State1 = handle_nodedown(Node, State),
  {noreply, State1};
handle_info(trim_nodes, State) ->
  trim_nodes(State),
  {noreply, State};
handle_info(Info, State) ->
  lager:debug("Unknown info: ~p", [Info]),
  {noreply, State}.

terminate(Reason, State) ->
  lager:debug("Lashup_GM terminated, because: ~p, in state: ~p", [Reason, State]),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_sync(Pid, _State) ->
  lashup_gm_sync_worker:handle(Pid).

%% @private Generates new epoch
-spec(new_epoch() -> non_neg_integer()).
new_epoch() ->
  WorkDir = lashup_config:work_dir(),
  EpochFilename = filename:join(WorkDir, "lashup_gm_epoch"),
  case lashup_save:read(EpochFilename) of
    not_found ->
      Epoch = erlang:system_time(seconds),
      Data = #{epoch => Epoch},
      ok = lashup_save:write(EpochFilename, term_to_binary(Data)),
      Epoch;
    {ok, BinaryData} ->
      OldData = #{epoch := OldEpoch} = binary_to_term(BinaryData),
      %% Should we check if our time is (Too far) behind the last epoch?
      NewEpoch = max(erlang:system_time(seconds), OldEpoch) + 1,
      NewData = OldData#{epoch := NewEpoch},
      ok = lashup_save:write(EpochFilename, term_to_binary(NewData)),
      NewEpoch
  end.

-spec(handle_subscribe(Pid :: pid(), State :: state()) -> {{ok, Self :: pid()}, State1 :: state()}).
handle_subscribe(Pid, State = #state{subscribers = Subscribers}) ->
  MonitorRef = monitor(process, Pid),
  Subscriber = #subscriber{node = node(Pid), monitor_ref = MonitorRef, pid = Pid},
  State1 = State#state{subscribers = [Subscriber | Subscribers]},
  {{ok, self()}, State1}.

handle_current_views(ActiveView, State = #state{subscriptions = Subscriptions}) ->
  Subscriptions1 = lists:foldl(fun check_member/2, Subscriptions, ActiveView),
  OldActiveView = State#state.active_view,
  case {ActiveView, Subscriptions} of
    {OldActiveView, Subscriptions1} ->
      ok;
    _ ->
      gen_server:cast(self(), update_node)
  end,
  State#state{subscriptions = Subscriptions1, active_view = ActiveView}.


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

%% @private Creates a new value the node
new_value(_State = #state{active_view = ActiveView, epoch = Epoch}) ->
  #{
    active_view => ActiveView,
    server_id => node(),
    epoch => Epoch,
    %% Positive looks nicer...
    clock => erlang:unique_integer([positive, monotonic])
  }.


%% @private Creates the first Member record representing the local node
init_node(State) ->
  LocalUpdate = erlang:system_time(nano_seconds),
  Value = new_value(State),
  Member = #member2{
    node = node(),
    last_heard = LocalUpdate,
    value = Value,
    active_view = maps:get(active_view, Value)
  },
  persist(Member, State).


%% @private Update the local node's DVVSet
update_node(Reason, State) ->
  NewValue = new_value(State),
  update_node(NewValue, Reason, State).

%% @private Take an updated Value from the local node, turn it into a message and propagate it
update_node(NewValue, Reason, State) ->
  %% TODO:
  %% Adjust TTL based on maximum path length from link-state database
  Message = #{
    message => updated_node,
    node => node(),
    ttl => 10,
    value => NewValue,
    reason => Reason
  },
  handle_updated_node(node(), Message, State).

handle_updated_node(_From, UpdatedNode = #{ttl := TTL}, State) when TTL < 0 ->
  lager:warning("TTL Exceeded on Updated Node: ~p", [UpdatedNode]),
  State;

handle_updated_node(From, UpdatedNode = #{node := Node}, State) ->
  case ets:lookup(members, Node) of
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
    value := Value
  }, State) ->
  LocalUpdate = erlang:monotonic_time(nano_seconds),
  Member = #member2{
    node = Node,
    last_heard = LocalUpdate,
    value = Value,
    active_view = maps:get(active_view, Value)
  },
  persist(Member, State),
  NewUpdatedNode = UpdatedNode#{exempt_nodes => [From], ttl => TTL - 1},
  forward(NewUpdatedNode, State),
  State.


maybe_store_store_and_forward_updated_node(Member, From, UpdatedNode = #{value := RemoteValue}, State) ->
  %% Should be true, if the remote one is newer
  #{epoch := RemoteEpoch, clock := RemoteClock} = RemoteValue,
  #{epoch := LocalEpoch, clock := LocalClock} = Member#member2.value,
  case {RemoteEpoch, RemoteClock} > {LocalEpoch, LocalClock}  of
    true ->
      store_and_forward_updated_node(Member, From, UpdatedNode, State);
    %% We've seen an old clock
    false ->
      ok
  end,
  State.

store_and_forward_updated_node(Member, From, _UpdatedNode, _State)
    when Member#member2.node == node() andalso From =/= node() ->
  ok;
store_and_forward_updated_node(Member, From,
  UpdatedNode = #{
    value := Value
  }, State)  ->
  update_local_member(Value, Member, State),
  NewUpdatedNode = UpdatedNode#{exempt_nodes => [From]},
  forward(NewUpdatedNode, State).


%% @doc update a local member, and persist it to ets, from a Value
%% The value is gauranteed to be bigger than the one we have now
update_local_member(Value, Member, State) ->
  Now = erlang:monotonic_time(nano_seconds),
  NewMember = Member#member2{
    last_heard = Now,
    value = Value,
    active_view = maps:get(active_view, Value)
  },
  process_new_member(Member, NewMember, State),
  persist(NewMember, State).


forward(_NewUpdatedNode = #{ttl := TTL}, _State) when TTL =< 0 ->
  ok;
forward(NewUpdatedNode = #{ttl := TTL}, _State = #state{subscribers = Subscribers}) ->
  NewUpdatedNode1 = NewUpdatedNode#{ttl := TTL - 1},
  %% This should be small enough, no need to compress
  CompressedTerm = term_to_binary(NewUpdatedNode1),
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
  LastHeard = Member#member2.last_heard,
  TimeSinceLastHeard = erlang:convert_time_unit(Now - LastHeard, native, milli_seconds),
  Node = #{
    node => Member#member2.node,
    time_since_last_heard => TimeSinceLastHeard,
    active_view => Member#member2.active_view
  },
  [Node | Acc].

trim_nodes(State) ->
  Now = erlang:monotonic_time(),
  Delta = erlang:convert_time_unit(86400, seconds, native),
  MatchSpec = ets:fun2ms(
    fun(Member = #member2{last_heard = LastHeard})
      when Now - LastHeard > Delta andalso Member#member2.node =/= node()
      -> Member
    end
  ),
  Members = ets:select(members, MatchSpec),
  lists:foreach(fun(X) -> delete(X, State) end, Members).

update_node_backoff_loop(Delay, Pid) ->
  timer:sleep(Delay),
  Backoff = gen_server:call(?MODULE, update_node, infinity),
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
-spec(process_new_member(MemberOld :: member2(), MemberNew :: member2(), State :: state()) -> ok).
process_new_member(Member, NewMember, _State = #state{active_view = HyparViewActiveView}) ->
  ActiveView1 = Member#member2.active_view,
  ActiveView2 = NewMember#member2.active_view,
  ActiveView1Set = ordsets:from_list(ActiveView1),
  ActiveView2Set = ordsets:from_list(ActiveView2),
  RetiredMembersSet = ordsets:subtract(ActiveView1Set, ActiveView2Set),
  HyparViewActiveViewSet = ordsets:from_list(HyparViewActiveView),
  ProbeNodes = ordsets:intersection(RetiredMembersSet, HyparViewActiveViewSet),
  [lashup_hyparview_ping_handler:ping(ProbeNode) || ProbeNode <- ProbeNodes],
  ok.

handle_get_neighbor_recommendations(ActiveViewSize) ->
  MatchSpec = ets:fun2ms(
    fun(Member = #member2{active_view = ActiveView})
      when length(ActiveView) < ActiveViewSize andalso Member#member2.node =/= node()
      -> Member#member2.node
    end
  ),
  case ets:select(members, MatchSpec, 100) of
    {Members, _Continuation} ->
      [Member|_] = lashup_utils:shuffle_list(Members),
      {ok, Member};
    '$end_of_table' ->
      false
  end.

%% ETS write functions
delete(Member = #member2{}, _State) ->
  lashup_gm_route:delete_node(Member#member2.node),
  ets:delete(members, Member#member2.node).


%% TODO:
%% Rewrite both
-spec(persist(Member :: member2(), State :: state()) -> ok).
persist(Member, _State) ->
  lashup_gm_route:update_node(Member#member2.node, Member#member2.active_view),
  case ets:lookup(members, Member#member2.node) of
    [OldMember] ->
      ets:insert(members, Member),
      lashup_gm_events:ingest(OldMember, Member);
    [] ->
      ets:insert(members, Member),
      lashup_gm_events:ingest(Member)
  end,
  %% Find the component I'm part of
  ok.
