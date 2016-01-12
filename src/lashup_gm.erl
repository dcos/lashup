%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 15. Jan 2016 2:56 AM
%%%-------------------------------------------------------------------

-module(lashup_gm).
-author("sdhillon").


-behaviour(gen_server).

%% API
-export([start_link/0,
  dump_events/1,
  get_subscriptions/0,
  gm/0,
  path_to/1,
  get_digraph/0,
  multicast/1,
  set_metadata/1,
  get_neighbor_recommendations/1,
  reachable/1,
  reachable/2]).

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
-record(state, {subscriptions = [], init_time, vclock_id, seed, active_view = [], metadata = undefined, digraph, subscribers = []}).

%% TODO: Implement probes

%%%===================================================================
%%% API
%%%===================================================================
-spec(reachable(IP :: inet:ip4_address(), Digraph :: digraph:graph()) -> true | false | maybe).
reachable(IP, Digraph) ->
  NodeIPs = ets:lookup(node_ips, IP),
  Nodes = [Node || {_IP, Node} <- NodeIPs],
  Reachability = [digraph:get_path(Digraph, node(), Node) || Node <- Nodes],
  case {lists:member(true, Reachability), lists:member(false, Reachability)} of
    %% We have both trues and falses
    {true, true} ->
      maybe;
    %% We have no trues, and only falses
    {false, true} ->
      false;
    %% We have no trues, and no falses
    {false, false} ->
      maybe;
    %% We have only falses and no truths
    {true, false} ->
      true
  end.
-spec(reachable(IP :: inet:ip4_address()) -> true | false | maybe).
reachable(IP) ->
  reachable(IP, get_digraph()).

get_digraph() ->
  gen_server:call(?SERVER, get_digraph).

path_to(Node) ->
  gen_server:call(?SERVER, {path_to, Node}).

set_metadata(Metadata) ->
  gen_server:call(?SERVER, {set_metadata, Metadata}).

get_neighbor_recommendations(ActiveViewSize) ->
  gen_server:call(?SERVER, {get_neighbor_recommendations, ActiveViewSize}, 10).

gm() ->
  gen_server:call(?SERVER, gm).

get_subscriptions() ->
  gen_server:call(?SERVER, get_subscriptions).

dump_events(Pid) ->
  gen_server:cast(?SERVER, {dump_events, Pid}).

multicast(Payload) ->
  gen_server:cast(?SERVER, {multicast, Payload}).
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
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  random:seed(lashup_utils:seed()),
  %% TODO: Add jitter
  MyPid = self(),
  spawn_link(fun() -> update_node_backoff_loop(5000, MyPid) end),
  ets:new(node_ips, [bag, named_table]),
  ets:new(members, [ordered_set, named_table, {keypos, #member.nodekey}]),
  lashup_hyparview_events:subscribe(fun(Event) -> gen_server:cast(?SERVER, #{message => lashup_hyparview_event, event => Event}) end),
  VClockID = {node(), erlang:phash2(random:uniform())},
  Metadata = base_metadata(),
  State = #state{init_time = erlang:monotonic_time(), vclock_id = VClockID, seed = lashup_utils:seed(), digraph = digraph:new(), metadata = Metadata},
  init_clock(State),
  timer:send_interval(3600*1000, trim_nodes),
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
  State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call({set_metadata, Metadata}, _From, State) ->
  BaseMetadata = base_metadata(),
  %% Metadata can override values in BaseMetadata
  NewMetadata = maps:merge(BaseMetadata, Metadata),
  State1 = State#state{metadata = NewMetadata},
  self() ! update_node,
  {reply, ok, State1};
handle_call(get_digraph, _From, State = #state{digraph = Digraph}) ->
  Reply = {ok, Digraph},
  {reply, Reply, State};
handle_call({path_to, Node}, _From, State = #state{digraph = Digraph}) ->
  Reply = digraph:get_short_path(Digraph, node(), Node),
  {reply, Reply, State};
handle_call(gm, _From, State) ->
  Reply = get_membership(),
  {reply, Reply, State};
handle_call({multicast, Payload}, _From, State) ->
  do_multicast(Payload, State);
handle_call({subscribe, Pid}, _From, State = #state{subscribers = Subscribers}) ->
  MonitorRef = monitor(process, Pid),
  Subscriber = #subscriber{node = node(Pid), monitor_ref = MonitorRef, pid = Pid},
  State1 = State#state{subscribers = [Subscriber|Subscribers]},
  {reply, {ok, self()}, State1};
handle_call(get_subscriptions, _From, State = #state{subscriptions =  Subscriptions}) ->
  {reply, Subscriptions, State};
handle_call(update_node, _From, State) ->
  State1 = update_node(State),
  {reply, 300000, State1};
handle_call({get_neighbor_recommendations, ActiveViewSize}, _From, State) ->
  Reply = handle_get_neighbor_recommendations(ActiveViewSize),
  {reply, Reply, State};
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
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({dump_events, Pid}, State) ->
  handle_dump_events(Pid, State),
  {noreply, State};
handle_cast({compressed, Data}, State) when is_binary(Data) ->
  Data1 = binary_to_term(Data),
  handle_cast(Data1, State);

handle_cast(#{message := remote_event, from := From, event := #{message := updated_node} = UpdatedNode}, State) ->
  %lager:debug("Received Updated Node: ~p", [UpdatedNode]),
  State1 = handle_updated_node(From, UpdatedNode, State),
  {noreply, State1};

handle_cast(#{message := lashup_hyparview_event, event := #{type := current_views} = Event}, State) ->
  State1 = handle_current_views(Event, State),
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
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_info(_Down = {'DOWN', MonitorRef, _Type, _Object, _Info}, State) when is_reference(MonitorRef) ->
  State1 = prune_subscribers(MonitorRef, State),
  State2 = prune_subscriptions(MonitorRef, State1),
  {noreply, State2};

handle_info({nodedown, Node}, State) ->
  State1 = handle_nodedown(Node, State),
  {noreply, State1};
handle_info(update_node, State) ->
  State1 = update_node(State),
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
  State :: #state{}) -> term()).
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
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
  Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_current_views(_Event = #{active_view := RemoteActiveView}, State = #state{subscriptions = Subscriptions}) ->
  Subscriptions1 = lists:foldl(fun check_member/2, Subscriptions, RemoteActiveView),
  OldActiveView = State#state.active_view,
  case {RemoteActiveView, Subscriptions} of
    {OldActiveView, Subscriptions1} ->
      ok;
    _ ->
      self() ! update_node
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
            [Subscription|Subscriptions];
          Else ->
            lager:debug("Unable to add handler for node: ~p, error: ~p", [Node, Else]),
            Subscriptions
      end;
    _ ->
      Subscriptions
  end.

init_clock(State = #state{vclock_id = VClockID}) ->
  %% Write the first clock
  VClock = riak_dt_vclock:fresh(),
  VClock1 = riak_dt_vclock:increment(VClockID, VClock),
  NodeClock = erlang:system_time(),
  LocalUpdate = erlang:monotonic_time(),
  ClockDelta = abs(NodeClock - LocalUpdate),
  Member = #member{node = node(),
    nodekey = nodekey(node(), State),
    node_clock = NodeClock,
    vclock = VClock1,
    locally_updated_at = [LocalUpdate],
    clock_deltas = [ClockDelta],
    metadata = State#state.metadata
    },
  persist(Member, State).

nodekey(Node, _State = #state{seed = Seed}) ->
  Hash = erlang:phash2({Node, Seed}),
  {Hash, Node};
nodekey(Node, Seed) ->
  Hash = erlang:phash2({Node, Seed}),
  {Hash, Node}.

update_node(State = #state{vclock_id = VClockID, active_view = ActiveView, metadata = Metadata}) ->
  [Member] = ets:lookup(members, nodekey(node(), State)),
  NewVClock = riak_dt_vclock:increment(VClockID, Member#member.vclock),
  %% TODO:
  %% Adjust TTL based on maximum path length from link-state database
  Message = #{
    message => updated_node,
    node => node(),
    node_clock => erlang:system_time(),
    vclock => NewVClock,
    active_view => ActiveView,
    ttl => 10,
    metadata => Metadata
  },
  handle_updated_node(node(), Message, State).

handle_updated_node(_From, UpdatedNode = #{ttl := TTL}, State) when TTL < 0 ->
  lager:warning("TTL Exceeded on Updated Node: ~p", [UpdatedNode]),
  State;

handle_updated_node(From, UpdatedNode = #{node := Node}, State) ->
  %% Update local state
  %% 1. If we've seen it before, drop it
  %% 2. If we haven't seen this update before, go ahead and forward it
  %% 3. If our version is newer, drop the update, and send back our version
  case ets:lookup(members, nodekey(Node, State)) of
    [] ->
      %% Brand new, store it
      store_and_forward_new_updated_node(From, UpdatedNode, State);
    [Member] ->
      maybe_store_store_and_forward_updated_node(Member, From, UpdatedNode, State)
  end.

store_and_forward_new_updated_node(From,
    UpdatedNode = #{node := Node, node_clock := NodeClock, vclock := VClock, ttl := TTL, active_view := ActiveView, metadata := Metadata}, State) ->
  LocalUpdate = erlang:monotonic_time(),
  ClockDelta = abs(NodeClock - LocalUpdate),
  Member = #member{
    node = Node,
    nodekey = nodekey(Node, State),
    node_clock = NodeClock,
    vclock = VClock,
    locally_updated_at = [LocalUpdate],
    clock_deltas = [ClockDelta],
    active_view = ActiveView,
    metadata = Metadata
  },
  persist(Member, State),
  NewUpdatedNode = UpdatedNode#{exempt_nodes => [From], ttl => TTL - 1},
  forward(NewUpdatedNode, State),
  State.


maybe_store_store_and_forward_updated_node(Member, From, UpdatedNode = #{vclock := VClock}, State) ->
  %% Check if the remote vector clock is bigger
  case lashup_utils:compare_vclocks(VClock, Member#member.vclock) of
    gt ->
      %lager:debug("Storing and forwarding updated node: ~p", [UpdatedNode]),
      store_and_forward_updated_node(Member, From, UpdatedNode, State);
    lt ->
      %lager:debug("Dropping updated node: ~p", [UpdatedNode]),
      drop_and_respond_updated_node(Member, From, UpdatedNode, State);
    equal ->
      %lager:debug("Dup msg: ~p", [UpdatedNode]),
      ok;
    concurrent ->
      %lager:debug("Merging and forwarding: ~p", [UpdatedNode]),
      merge_and_forward_updated_node(Member, From, UpdatedNode, State)
  end,
  State.

%-record(member, {nodekey, node, node_clock, vclock, locally_updated_at = [], clock_deltas = []}).

store_and_forward_updated_node(Member, From, _UpdatedNode, _State) when Member#member.node == node() andalso From =/= node() ->
  ok;

store_and_forward_updated_node(Member, From,
    UpdatedNode = #{node_clock := NodeClock, vclock := VClock, ttl := TTL, active_view := ActiveView, metadata := Metadata}, State) when TTL >= 0 ->
  Now = erlang:monotonic_time(),
  NewLocallyUpdatedAt = lists:sublist([Now | Member#member.locally_updated_at], 100),
  ClockDelta = abs(NodeClock - Now),
  NewClockDelta = lists:sublist([ClockDelta|Member#member.clock_deltas], 100),
  NewMember = Member#member{
    node_clock = NodeClock,
    vclock = VClock,
    locally_updated_at = NewLocallyUpdatedAt,
    clock_deltas = NewClockDelta,
    active_view = ActiveView,
    metadata = Metadata
  },
  process_new_member(Member, NewMember, State),
  persist(NewMember, State),
  NewUpdatedNode = UpdatedNode#{exempt_nodes => [From], ttl := TTL - 1},
  forward(NewUpdatedNode, State);
store_and_forward_updated_node(_Member, _From, _UpdatedNode, _State) ->
  ok.

drop_and_respond_updated_node(Member, From, UpdatedNode, State) ->
  NewUpdatedNode = UpdatedNode#{
    node_clock => Member#member.node_clock,
    vclock => Member#member.vclock,
    active_view => Member#member.active_view,
    only_nodes => [From],
    metadata => Member#member.metadata
  },
  forward(NewUpdatedNode, State).

%% We can't actually update the vector clock with our vector clock if we're some random node
%% We only do the update if and only if we have the same node name as the ingress message

merge_and_forward_updated_node(Member, _From, UpdatedNode = #{vclock := VClock, node := Node, ttl := TTL},
    State = #state{vclock_id = VClockID, active_view = ActiveView, metadata = Metadata}) when Node == node() andalso TTL > 0 ->
  lager:warning("Saw member with duplicate node name, merging vclocks"),
  NewVClock = riak_dt_vclock:merge([VClock, Member#member.vclock]),
  NewVClock1 = riak_dt_vclock:increment(VClockID, NewVClock),
  NewNodeClock = erlang:system_time(),
  Now = erlang:monotonic_time(),
  NewLocallyUpdatedAt = lists:sublist([Now | Member#member.locally_updated_at], 100),
  ClockDelta = abs(NewNodeClock - Now),
  NewClockDelta = lists:sublist([ClockDelta|Member#member.clock_deltas], 100),
  NewMember = Member#member{
    node_clock = NewNodeClock,
    vclock = NewVClock1,
    locally_updated_at = NewLocallyUpdatedAt,
    clock_deltas = NewClockDelta,
    metadata = Metadata
  },
  NewUpdatedNode = UpdatedNode#{node_clock => NewNodeClock, vclock => NewVClock1, ttl := TTL - 1, active_view => ActiveView, metadata => Metadata},
  persist(NewMember, State),
  forward(NewUpdatedNode, State);

%% Drop the local version completely
merge_and_forward_updated_node(Member, From, UpdatedNode = #{ttl := TTL}, State) when TTL >= 0 ->
  %% We delete this state locally
  %% Unless it's the member that originated the message
  case From of
    Node when Node == Member#member.node ->
      NewUpdatedNode = UpdatedNode#{only_nodes => [Node],ttl := TTL - 1, node_clock => Member#member.node_clock, vclock => Member#member.vclock, active_view => Member#member.active_view, metadata => Member#member.metadata},
      forward(NewUpdatedNode, State);
    _ -> ok
  end,
  delete(Member, State).


forward(_NewUpdatedNode = #{ttl := TTL}, _State) when TTL =< 0->
  ok;
forward(NewUpdatedNode, _State = #state{subscribers = Subscribers}) ->
  CompressedTerm = term_to_binary(NewUpdatedNode, [compressed]),
  Fun =
  fun(_Subscriber = #subscriber{pid = Pid}) ->
    erlang:send(Pid, {event, CompressedTerm}, [noconnect])
  end,
  lists:foreach(Fun, Subscribers).

handle_dump_events(Pid, State) ->
  Key = ets:first(members),
  do_dump_events(Key, Pid, State).

do_dump_events('$end_of_table', _Pid, _State) ->
  ok;
do_dump_events(Key, Pid, _State) ->
  [Member] = ets:lookup(members, Key),
  NewUpdatedNode = to_event(Member),
  CompressedTerm = term_to_binary(NewUpdatedNode, [compressed]),
  erlang:send(Pid, {event, CompressedTerm}, [noconnect]),
  NextKey = ets:next(members, Key),
  do_dump_events(NextKey, Pid, _State).

to_event(Member = #member{}) ->
  #{
    message => updated_node,
    node => Member#member.node,
    node_clock => Member#member.node_clock,
    vclock => Member#member.vclock,
    ttl => 1,
    active_view => Member#member.active_view,
    metadata => Member#member.metadata
  }.



handle_nodedown(Node, State = #state{subscriptions = Subscriptions, subscribers = Subscribers}) ->
  lager:debug("Removing subscription (nodedown) from node: ~p", [Node]),
  Subscriptions1 = lists:keydelete(Node, #subscription.node, Subscriptions),
  Subscribers1 = lists:keydelete(Node, #subscriber.node, Subscribers),
  State#state{subscriptions = Subscriptions1, subscribers = Subscribers1}.

get_membership() ->
  ets:foldl(fun accumulate_membership/2, [], members).

% -record(member, {nodekey, node, node_clock, vclock, locally_updated_at = [], clock_deltas = []}).

accumulate_membership(Member, Acc) ->
  Now = erlang:monotonic_time(),
  [LastHeard| _] = Member#member.locally_updated_at,
  TimeSinceLastHeard = erlang:convert_time_unit(Now - LastHeard, native, milli_seconds),
  Node = #{node => Member#member.node, time_since_last_heard => TimeSinceLastHeard, metadata => Member#member.metadata},
  [Node|Acc].

trim_nodes(State) ->
  Now = erlang:monotonic_time(),
  Delta = erlang:convert_time_unit(86400, seconds, native),
  Members =
    ets:foldl(members, [],
      fun(Member = #member{locally_updated_at = [LastHeard | _]}, Acc) when Now - LastHeard > Delta ->
        [Member | Acc];
        (_, Acc) ->
          Acc
      end
    ),
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

%handle_multicast(Message, State = #state{digraph = Digraph}) ->


%% This function (at the moment) only triggers for the purposes to hint back to hyparview membership for aggressive probes
process_new_member(Member, NewMember, _State = #state{active_view = HyparViewActiveView}) ->
  ActiveView1 = Member#member.active_view,
  ActiveView2 = NewMember#member.active_view,
  ActiveView1Set = ordsets:from_list(ActiveView1),
  ActiveView2Set = ordsets:from_list(ActiveView2),
  RetiredMembersSet = ordsets:subtract(ActiveView1Set, ActiveView2Set),
  HyparViewActiveViewSet = ordsets:from_list(HyparViewActiveView),
  ProbeNodes = ordsets:intersection(RetiredMembersSet, HyparViewActiveViewSet),
  lists:foreach(fun(ProbeNode) -> gen_server:cast(lashup_hyparview_membership, {probe, ProbeNode}) end, ProbeNodes).

do_multicast(_Payload, _State) ->
  %#{message => multicast, ttl => 20, payload => Payload}
  ok.
 % Message = #{message => multicast, from => node(), payload => Payload},

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
delete(Member = #member{}, _State = #state{digraph = Digraph}) ->
  case ets:lookup(members, Member#member.nodekey) of
    [Member] ->
      delete_node_ips(Member),
      digraph:del_vertex(Member#member.node, Digraph),
      ets:delete(members, Member#member.nodekey),
      ok;
    [] ->
      ok
  end.

delete_node_ips(Member = #member{metadata = #{ips := IPs}}) ->
  lists:foreach(fun(IP) -> ets:delete(node_ips, {IP, Member#member.node}) end, IPs);
delete_node_ips(_Member) ->
  ok.



persist(Member, _State = #state{digraph = Digraph}) ->
  case ets:lookup(members, Member#member.nodekey) of
    [_OldMember = #member{metadata = #{ips := OldIPs}}] ->
      NewIPs = maps:get(ips, Member#member.metadata, []),
      IPsToRemove = OldIPs -- NewIPs,
      IPsToAdd = NewIPs -- OldIPs,
      lists:foreach(fun(IP) -> ets:delete(node_ips, {IP, Member#member.node}) end, IPsToRemove),
      RecordsToAdd = [{IP, Member#member.node} || IP <- IPsToAdd],
      ets:insert(node_ips, RecordsToAdd),
      lists:foreach(fun(X) -> digraph:del_edge(Digraph, X) end, digraph:out_edges(Digraph, Member#member.node));
    [] ->
      IPsToAdd = maps:get(ips, Member#member.metadata, []),
      RecordsToAdd = [{IP, Member#member.node} || IP <- IPsToAdd],
      ets:insert(node_ips, RecordsToAdd),
      digraph:add_vertex(Digraph, Member#member.node),
      ok
  end,
  NewNeighbors = Member#member.active_view,
  lists:foreach(fun(X) -> digraph:add_vertex(Digraph, X), digraph:add_edge(Digraph, Member#member.node, X) end, NewNeighbors),
  ets:insert(members, Member).

base_metadata() ->
  {ok, Socket} = gen_udp:open(0),
  IPAddress =
    case inet:gethostbyname("leader.mesos") of
      {ok, Hostent} ->
        [Addr|_] = Hostent#hostent.h_addr_list,
        Addr;
      _ ->
        {192, 88, 99, 0}
    end,
  %% This is an undocumented feature :).
  inet_udp:connect(Socket, IPAddress, 4),
  {ok, {Address, _LocalPort}} = inet:sockname(Socket),
  gen_udp:close(Socket),
  case lashup_utils:get_dcos_ip() of
    false ->
      #{ips => [Address]};
    IP ->
      #{ips => [Address, IP]}
  end.


