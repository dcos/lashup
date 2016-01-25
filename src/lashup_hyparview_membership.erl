%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Dec 2015 10:57 AM
%%%-------------------------------------------------------------------
-module(lashup_hyparview_membership).
-author("sdhillon").

-behaviour(gen_server).

%% API
-export([
  start_link/0,
  get_active_view/0,
  get_passive_view/0,
  poll_for_master_nodes/0
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-include("lashup.hrl").
%% These are the constants for the sizes of views from the lashup paper
-define(K, 6).

%% The original C was 1
%% I think for our use-case, we can bump it to 3?
-define(C, 1).
% This number is actually log10(10000)
-define(LOG_TOTAL_MEMBERS, 4).

-define(ACTIVE_VIEW_SIZE, ?LOG_TOTAL_MEMBERS + ?C).
-define(PASSIVE_VIEW_SIZE, ?K * (?LOG_TOTAL_MEMBERS + ?C)).
%% The interval that we try to join the contact nodes in milliseconds
-define(JOIN_INTERVAL, 1000).
-define(NEIGHBOR_INTERVAL, 10000).

-define(SHUFFLE_INTERVAL, 60000).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(SERVER, ?MODULE).

-record(monitor, {monitor_ref, node}).

-record(state, {
  active_view = ordsets:new(),
  passive_view = ordsets:new(),
  monitors = [],
  fixed_seed,
  idx = 1,
  unfilled_active_set_count = 0,
  init_time =  erlang:error(init_time_unset),
  messages = [],
  join_window,
  pings_in_flight = orddict:new(),
  ping_idx = 1,
  joined = false,
  extra_masters = []
}).

%%%===================================================================
%%% API
%%%===================================================================


get_active_view() ->
  gen_server:call(?SERVER, get_active_view).

get_passive_view() ->
  gen_server:call(?SERVER, get_passive_view).

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
  random:seed(erlang:phash2([node()]),
    erlang:monotonic_time(),
    erlang:unique_integer()),

  %% This seed is a fixed seed used for shuffling the list
  FixedSeed = seed(),
  MyPid = self(),
  spawn_link(fun() -> shuffle_backoff_loop(5000, MyPid) end),
  %% Try to get in touch with contact node(s)
  reschedule_join(15000),
  %% Schedule the maybe_neighbor
  reschedule_maybe_neighbor(30000),
  Window = lashup_utils:new_window(1000),
  reschedule_ping(60000),
  spawn(?MODULE, poll_for_master_nodes, []),
  {ok, _} = timer:apply_after(5000, ?MODULE, poll_for_master_nodes, []),
  {ok, _} = timer:apply_after(15000, ?MODULE, poll_for_master_nodes, []),
  {ok, _} = timer:apply_after(60000, ?MODULE, poll_for_master_nodes, []),
  {ok, _} = timer:apply_after(120000, ?MODULE, poll_for_master_nodes, []),

  %% Only poll every 60 minutes beyond that
  {ok, _} = timer:apply_interval(3600 * 1000, ?MODULE, poll_for_master_nodes, []),
  {ok, #state{passive_view = contact_nodes([]), fixed_seed = FixedSeed, init_time = erlang:system_time(), join_window = Window}}.

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

handle_call(get_active_view, _From, State = #state{active_view = ActiveView}) ->
  {reply, ActiveView, State};
handle_call(get_passive_view, _From, State = #state{passive_view = PassiveView}) ->
  {reply, PassiveView, State};
handle_call(try_shuffle, _From, State)  ->
  NewDelay = try_shuffle(State),
  {reply, NewDelay, State};
handle_call(_Request, _From, State) ->
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
%% We generated a timer (with a ref) when we did the join with a timeout
%% We get passed back that ref, and now we need to delete it
handle_cast({do_probe, Node}, State) ->
  State1 = handle_do_probe(Node, State),
  {noreply, check_state(State1)};
handle_cast(_JoinSuccess = #{message := join_success, sender := Sender, ref := Ref, passive_view := RemotePassiveView}, State) ->
  State1 = add_node_active_view(Sender, State),
  State2 =
  case timer:cancel(Ref) of
    {ok, cancel} ->
      lager:debug("Node ~p successfully joined node ~p", [node(), Sender]),
      lists:foldl(fun maybe_add_node_passive_view/2, State, RemotePassiveView);
    {error, _Reason} ->
      lager:info("Received late join success from Node: ~p", [Sender]),
      State1
  end,
  State3 = State2#state{joined = true},
  push_state(State3),
  {noreply, check_state(State3)};
handle_cast(_Join = #{message := join, sender := Node, ref := Ref}, State) ->
  lager:debug("Saw join from ~p", [Node]),
  State1 = handle_join(Node, State, Ref),
  push_state(State1),
  {noreply, check_state(State1)};
handle_cast(ForwardJoin = #{message := forward_join}, State) ->
  State1 = handle_forward_join(ForwardJoin, State),
  push_state(State1),
  {noreply, check_state(State1)};
handle_cast(Disconnect = #{message := disconnect}, State) ->
  State1 = handle_disconnect(Disconnect, State),
  push_state(State1),
  {noreply, check_state(State1)};
handle_cast(Neighbor = #{message := neighbor}, State) ->
  State1 = handle_neighbor(Neighbor, State),
  push_state(State1),
  {noreply, check_state(State1)};
handle_cast(_NeighborDeny = #{message := neighbor_deny, sender := Sender, ref := Ref}, State  = #state{active_view = ActiveView, passive_view = PassiveView}) ->
  timer:cancel(Ref),
  lager:debug("Denied from joining ~p, while active view ~p, passive view: ~p", [Sender, ActiveView, PassiveView]),
  push_state(State),
  schedule_disconnect(Sender),
  {noreply, check_state(State)};
handle_cast(_NeighborAccept = #{message := neighbor_accept, sender := Sender, ref := Ref}, State) ->
  timer:cancel(Ref),
  State1 = add_node_active_view(Sender, State),
  push_state(State1),
  {noreply, check_state(State1)};
handle_cast(Shuffle = #{message := shuffle}, State) ->
  State1 = handle_shuffle(Shuffle, State),
  push_state(State1),
  {noreply, check_state(State1)};
handle_cast(ShuffleReply = #{message := shuffle_reply}, State) ->
  State1 = handle_shuffle_reply(ShuffleReply, State),
  push_state(State1),
  {noreply, check_state(State1)};
handle_cast(GossipMessage = #{message := gossip}, State) ->
  State1 = handle_gossip_message(GossipMessage, State),
  {noreply, check_state(State1)};
handle_cast(PingMessage = #{message := ping}, State) ->
  handle_ping(PingMessage, State),
  {noreply, State};
handle_cast(PongMessage = #{message := pong}, State) ->
  State1 = handle_pong(PongMessage, State),
  {noreply, check_state(State1)};
handle_cast({masters, List}, State) ->
  MasterSet = ordsets:del_element(node(), List),
  State1 = State#state{extra_masters = MasterSet},
  {noreply, check_state(State1)};
handle_cast(Request, State) ->
  lager:debug("Received unknown cast: ~p", [Request]),
  {noreply, check_state(State)}.

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
%% It's likely just that someone connected to us, and that's okay
handle_info(DownMessage = {'DOWN', _, _, _, _}, State) ->
  State1 = handle_down_message(DownMessage, State),
  push_state(State1),
  {noreply, check_state(State1)};
%% We don't need a full active view
%% In fact, the network can get into (healthy) cases where it's not possible
%% Like running fewer than the active view size count nodes
%% So, only neighbor if more than 25% of our active view is open.
handle_info(maybe_neighbor, State = #state{active_view = ActiveView}) when length(ActiveView) >= ?ACTIVE_VIEW_SIZE * 0.75 ->
  %% Ignore this, because my active view is full
  reschedule_maybe_neighbor(),
  State1 = State#state{unfilled_active_set_count = 0},
  {noreply, check_state(State1)};
handle_info(maybe_neighbor, State) ->
  lager:debug("Maybe neighbor triggered"),
  State1 = maybe_neighbor(State),
  push_state(State1),
  {noreply, check_state(State1)};
%% Stop trying to join is somehow someone connects to us
handle_info(join_failed, State = #state{active_view = ActiveView}) when length(ActiveView) > 0 ->
  {noreply, State};
handle_info(join_failed, State) ->
  lager:debug("Attempt to join timed out, rescheduling"),
  reschedule_join(),
  {noreply, State};
handle_info(try_join, State = #state{joined = true}) ->
  {noreply, State};
handle_info(try_join, State) ->
  try_do_join(State),
  {noreply, State};
handle_info({tried_neighbor, Node}, State = #state{passive_view = PassiveView}) ->
  PassiveView1 = ordsets:del_element(Node, PassiveView),
  State1 = State#state{passive_view = PassiveView1},
  push_state(State1),
  {noreply, check_state(State1)};
handle_info(ping_rq, State) ->
  State1 = handle_ping_rq(State),
  {noreply, check_state(State1)};
handle_info({ping_failed, Node}, State) ->
  State1 = handle_ping_failed(Node, State),
  {noreply, check_state(State1)};
handle_info({maybe_disconnect, Node}, State) ->
  State1 = handle_maybe_disconnect(Node, State),
  {noreply, check_state(State1)};
handle_info(Info, State) ->
  lager:debug("Received unknown info: ~p", [Info]),
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
  lager:error("Terminating with reason ~p, and state: ~p", [Reason, State]),
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


%% Ping every one of my neighbors at least every second

reschedule_ping() ->
  reschedule_ping(100).

reschedule_ping(Time) ->
  RandFloat = random:uniform(),
  Multipler = 1 + round(RandFloat),
  Delay = Multipler * Time,
  timer:send_after(Delay, ping_rq).



reschedule_maybe_neighbor() ->
  reschedule_maybe_neighbor(?NEIGHBOR_INTERVAL).
reschedule_maybe_neighbor(Time) ->
  RandFloat = random:uniform(),
  Multipler = 1 + round(RandFloat),
  Delay = Multipler * Time,
  timer:send_after(Delay, maybe_neighbor).

reschedule_join() ->
  reschedule_join(?JOIN_INTERVAL).

reschedule_join(BaseTime) ->
  RandFloat = random:uniform(),
  Multipler = 1 + round(RandFloat),
  timer:send_after(Multipler * BaseTime, try_join).



choose_node(Nodes) when length(Nodes) > 0 ->
  Length = erlang:length(Nodes),
  NodeIdx = random:uniform(Length),
  lists:nth(NodeIdx, Nodes).

-spec try_do_join(State :: #state{}) -> error | ok.
try_do_join(State) ->
  case do_join(State) of
    ok ->
      ok;
    true ->
      ok;
    _ ->
      reschedule_join(),
      error
  end.

do_join(State) ->
  ContactNodes = contact_nodes(State),
  lager:debug("Contact nodes found during join: ~p", [ContactNodes]),
  case ContactNodes of
    [] ->
      false;
    _ ->
      Node = choose_node(ContactNodes),
      try_connect_then_join(Node)
  end.

-spec try_connect_then_join(node()) -> boolean().
try_connect_then_join(Node) ->
  case net_adm:ping(Node) of
    pong ->
      try_join(Node);
    _ ->
      {error, could_not_connect}
  end.

-spec try_join(node()) -> boolean().
try_join(Node) ->
  {ok, Ref} = timer:send_after(1000, join_failed),
  case gen_server:cast({?SERVER, Node}, #{message => join, sender => node(), ref => Ref}) of
    ok ->
      lager:debug("Maybe joined: ~p", [Node]),
      ok;
    Else ->
      lager:warning("Error trying to join node ~p: ~p", [Node, Else]),
      {error, {unknown, Else}}
  end.


%% This is ridiculously inefficient on the order of O(N!),
%% but I'm prototyping
%% And this input shouldn't get much bigger than 30.


-spec(trim_ordset_to(ordsets:ordset(), non_neg_integer()) -> {ordsets:ordset(), ordsets:ordset()}).

trim_ordset_to(Ordset, Size) when Size > 0 ->
  trim_ordset_to(Ordset, Size, []).

trim_ordset_to(Ordset, Size, DroppedItems) when length(Ordset) > Size ->
  Idx = random:uniform(length(Ordset)),
  ItemToRemove = lists:nth(Idx, Ordset),
  Ordset1 = ordsets:del_element(ItemToRemove, Ordset),
  DroppedItems1 = ordsets:add_element(ItemToRemove, DroppedItems),
  trim_ordset_to(Ordset1, Size, DroppedItems1);
trim_ordset_to(Ordset, _Size, DroppedItems) ->
  {Ordset, DroppedItems}.




handle_join(Node, State = #state{join_window = JoinWindow, active_view = ActiveView}, Ref)
    when Node =/= node()->
  case lashup_utils:count_ticks(JoinWindow) of
    Num when length(ActiveView) == ?ACTIVE_VIEW_SIZE andalso Num < 25 ->
      really_handle_join(Node, State, Ref);
    %% If the active view is less than that, throttle to 1 / sec
    Num when Num < 1 ->
      really_handle_join(Node, State, Ref);
    %% Else, drop it
    WindowSize ->
      lager:warning("Throttling joins, window size: ~p, active view size: ~p", [WindowSize, length(ActiveView)]),
      State
  end.

really_handle_join(Node, State = #state{active_view = ActiveView, passive_view = PassiveView, monitors = Monitors, join_window = JoinWindow}, Ref) ->
  case try_add_node_to_active_view(Node, ActiveView, PassiveView, Monitors) of
    {ok, {ActiveView1, PassiveView1, Monitors1}} ->
      ARWL = lashup_config:arwl(),
      Fanout = ordsets:del_element(Node, ActiveView1),
      gen_server:abcast(Fanout, ?SERVER, #{message => forward_join, node => Node, ttl => ARWL, sender => node()}),
      Reply = #{message => join_success, sender => node(), ref => Ref, passive_view => PassiveView1},
      gen_server:cast({?SERVER, Node}, Reply),
      JoinWindow1 = lashup_utils:add_tick(JoinWindow),
      State#state{active_view = ActiveView1, passive_view = PassiveView1, monitors = Monitors1, join_window = JoinWindow1};
    error ->
      State
  end.



trim_active_view(ActiveView, PassiveView, Monitors, Size) ->
  {ActiveView1, DroppedNodes} = trim_ordset_to(ActiveView, Size),
  Monitors1 = lists:foldl(
    fun(Node, Acc) -> remove_monitor(Node, Acc) end, Monitors, DroppedNodes),
  gen_server:abcast(DroppedNodes, ?SERVER, #{message => disconnect, sender => node()}),
  PassiveView1 = ordsets:union(PassiveView, DroppedNodes),
  {ActiveView1, PassiveView1, Monitors1}.

try_add_node_to_active_view(Node, ActiveView, PassiveView, Monitors) when Node =/= node() ->
  %% There is one critical component here -
  %% We have to return a non-error code once we decide to trim from the active view
  %% If we don't, it could end with an asymmetrical graph
  case net_kernel:connect_node(Node) of
    true ->
      {ActiveView1, PassiveView1, Monitors1} = trim_active_view(ActiveView, PassiveView, Monitors, ?ACTIVE_VIEW_SIZE - 1),
      Monitors2 = ensure_monitor(Node, Monitors1),
      ActiveView2 = ordsets:add_element(Node, ActiveView1),
      PassiveView2 = ordsets:del_element(Node, PassiveView1),
      {ok, {ActiveView2, PassiveView2, Monitors2}};
    false ->
      lager:warning("Received join from node ~p, but could not connect back to it", [Node]),
      error
  end.


add_node_active_view(Node, State = #state{active_view = ActiveView, passive_view = PassiveView, monitors = Monitors}) when Node =/= node() ->
  {ActiveViewNew, PassiveViewNew, MonitorsNew} = case ordsets:is_element(Node, ActiveView) of
    true ->
      {ActiveView, PassiveView, Monitors};
    false ->
      lager:debug("Adding node ~p to active view", [Node]),
      case try_add_node_to_active_view(Node, ActiveView, PassiveView, Monitors) of
        {ok, {ActiveView1, PassiveView1, Monitors1}} ->
          {ActiveView1, PassiveView1, Monitors1};
        error ->
          {ActiveView, PassiveView, Monitors}
      end
  end,
  State#state{active_view = ActiveViewNew, passive_view = PassiveViewNew, monitors = MonitorsNew};
add_node_active_view(_Node, State) ->
  State.

maybe_add_node_passive_view(Node, State = #state{active_view = ActiveView, passive_view = PassiveView}) when Node =/= node() ->
  {ActiveViewNew, PassiveViewNew} = case {ordsets:is_element(Node, ActiveView), ordsets:is_element(Node, PassiveView)} of
    {false, false} ->
      {PassiveView1, _} = trim_ordset_to(PassiveView, ?PASSIVE_VIEW_SIZE - 1),
      PassiveView2 = ordsets:add_element(Node, PassiveView1),
      {ActiveView, PassiveView2};
    _ ->
      {ActiveView, PassiveView}
  end,
  State#state{active_view = ActiveViewNew, passive_view = PassiveViewNew};
maybe_add_node_passive_view(_Node, State) ->
  State.

handle_forward_join(_ForwardJoin = #{ttl := 0, node := Node}, State) ->
  add_node_active_view(Node, State);
handle_forward_join(_ForwardJoin = #{node := Node}, State = #state{active_view = []}) ->
  add_node_active_view(Node, State);
handle_forward_join(ForwardJoin = #{node := Node, ttl := TTL}, State) ->
  PRWL = lashup_config:prwl(),
  State1 = case TTL of
    PRWL ->
      maybe_add_node_passive_view(Node, State);
    _ ->
      State
  end,
  forward_forward_join(ForwardJoin, State1),
  State1.

forward_forward_join(ForwardJoin = #{ttl := TTL, sender := Sender, node := Node}, #state{active_view = ActiveView}) ->
  ForwardJoin1 = ForwardJoin#{ttl => TTL - 1, sender := node()},
  case ordsets:del_element(Sender, ActiveView) of
    [] ->
      lager:warning("Forwarding join original node ~p dropped", [Node]);
    Nodes ->
      Idx = random:uniform(length(Nodes)),
      TargetNode = lists:nth(Idx, Nodes),
      gen_server:cast({?SERVER, TargetNode}, ForwardJoin1)
  end.

%% TODO:
%% Maybe we should disconnect from the node at this point?
%% I'm unsure, because if another service is using hyparview for peer sampling
%% We could break the TCP connection before it's ready
handle_disconnect(_Disconnect = #{sender := Sender}, State = #state{active_view = ActiveView, passive_view = PassiveView, monitors = Monitors}) ->
  lager:info("Node ~p received disconnect from ~p", [node(), Sender]),
  MonitorRef = node_to_monitor_ref(Sender, Monitors),
  Monitors1 = remove_monitor(MonitorRef, Monitors),
  ActiveView1 = ordsets:del_element(Sender, ActiveView),
  PassiveView1 = ordsets:add_element(Sender, PassiveView),
  schedule_disconnect(Sender),
  State#state{active_view = ActiveView1, passive_view = PassiveView1, monitors = Monitors1}.


handle_down_message(_DownMessage = {'DOWN', MonitorRef, process, _Info, Reason}, State = #state{active_view = ActiveView, passive_view = PassiveView, monitors = Monitors}) ->
  case monitor_ref_to_node(MonitorRef, Monitors) of
    false ->
      State;
    Node ->
      lager:info("Lost active neighbor: ~p because: ~p", [Node, Reason]),
      Monitors1 = remove_monitor(MonitorRef, Monitors),
      ActiveView1 = ordsets:del_element(Node, ActiveView),
      PassiveView1 = ordsets:add_element(Node, PassiveView),
      State#state{active_view = ActiveView1, passive_view = PassiveView1, monitors = Monitors1}
  end.


%% Maybe neighbor should only be called if we have a non-full active view
%% We filter for a full active view in the handle_info callback.
maybe_neighbor(State = #state{joined = false, active_view = []}) ->
  reschedule_maybe_neighbor(10000),
  State;
maybe_neighbor(State = #state{joined = false}) ->
  %% The active view has someone in it
  %% Probably better to mark myself as joined
  reschedule_maybe_neighbor(500),
  State#state{joined = true};
maybe_neighbor(State = #state{passive_view = PassiveView, active_view = ActiveView, fixed_seed = FixedSeed, idx = Idx, unfilled_active_set_count = Count}) ->
  case {ActiveView, PassiveView} of
    %% Both views are empty
    %% This shouldn't happen
    %% Hydrate the passive view with contact nodes, and reschedule immediately
    {[], []} ->
      reschedule_maybe_neighbor(500),
      ContactNodes = ordsets:from_list(contact_nodes(State)),
      State#state{passive_view = ContactNodes};
    %% We have nodes in the active view, but none in the passive view
    %% This is concerning, but not necessarily bad
    %% Let's try to reconnect to the contact nodes
    {_ActiveView, []} ->
      reschedule_maybe_neighbor(10000),
      lager:warning("Trying to connect to connect to node from passive view, but passive view empty"),
      ContactNodes = ordsets:from_list(contact_nodes(State)),
      UnconnectedContactNodes = ordsets:subtract(ContactNodes, ActiveView),
      State#state{passive_view = UnconnectedContactNodes};
    %% If we have nodes in the passive view, let's try to connect to them
    %% One difference between our implementation and the paper is that it evicts nodes from the passive view
    %% after they fail to be connected to
    %% Given our PassiveView is bounded, we just circle through that list
    {[], PassiveView} ->
      reschedule_maybe_neighbor(500),
      send_neighbor(500, PassiveView, high, Idx, FixedSeed),
      State#state{idx = Idx + 1, unfilled_active_set_count = Count + 1};
    {_ActiveView, PassiveView} ->
      reschedule_maybe_neighbor(2000),
      State1 = maybe_gossip_for_neighbor(State),
      maybe_gm_neighbor(2000, State1),
      send_neighbor(2000, PassiveView, low, Idx, FixedSeed),
      State1#state{idx = Idx + 1, unfilled_active_set_count = Count + 1}
  end.

%% Timeout is actually a minimum time
maybe_gm_neighbor(Timeout, _State = #state{unfilled_active_set_count = Count})
    when Count rem 5 == 0 andalso Count > 3 ->
  case catch lashup_gm:get_neighbor_recommendations(?ACTIVE_VIEW_SIZE) of
    {ok, Node} ->
      send_neighbor_to(Timeout, Node, low),
      Node;
    _ ->
      ok
  end;
maybe_gm_neighbor(_Timeout, _State) ->
  ok.
send_neighbor(Timeout, PassiveView, Priority, Idx, FixedSeed) when length(PassiveView) > 0 ->
  ShuffledPassiveView = shuffle_list(PassiveView, FixedSeed),
  RealIdx = Idx rem length(ShuffledPassiveView) + 1,
  Node = lists:nth(RealIdx, ShuffledPassiveView),
  send_neighbor_to(Timeout, Node, Priority),
  Node.

%% TODO: Use lashup_gm's global view to choose the neighbor rather than this gossip jank
send_neighbor_to(Timeout, Node, Priority) ->
  lager:debug("Sending neighbor to: ~p", [Node]),
  Ref = timer:send_after(Timeout*3, {tried_neighbor, Node}),
  gen_server:cast({?SERVER, Node}, #{message => neighbor, ref => Ref, priority => Priority, sender => node()}).

handle_neighbor(_Neighbor = #{priority := low, sender := Sender, ref := Ref}, State = #state{active_view = ActiveView})
    when length(ActiveView) == ?ACTIVE_VIEW_SIZE ->
  %% The Active neighbor list is full
  lager:info("Denied neighbor request from ~p because active view full", [Sender]),
  gen_server:cast({?SERVER, Sender}, #{message => neighbor_deny, sender => node(), ref => Ref}),
  State;

%% Either this is a high priority request
%% Or I have an empty slot in my active view list
handle_neighbor(_Neighbor = #{sender := Sender, ref := Ref}, State = #state{active_view = ActiveView, passive_view = PassiveView, monitors = Monitors}) ->
  {ActiveViewNew, PassiveViewNew, MonitorsNew} =
    case try_add_node_to_active_view(Sender, ActiveView, PassiveView, Monitors) of
    {ok, {ActiveView1, PassiveView1, Monitors1}} ->
      gen_server:cast({?SERVER, Sender}, #{message => neighbor_accept, sender => node(), ref => Ref}),
      {ActiveView1, PassiveView1, Monitors1};
    error ->
      lager:warning("Failed to add neighbor ~p to active view on neighbor message", [Sender]),
      gen_server:cast({?SERVER, Sender}, #{message => neighbor_deny, sender => node(), ref => Ref}),
      {ActiveView, PassiveView, Monitors}
  end,
  State#state{active_view = ActiveViewNew, passive_view = PassiveViewNew, monitors = MonitorsNew}.

%% Gossip every 10 protocol periods, but wait at least 3 protocol periods before sending a randomize gossip
%% This should only be called if we don't have enough neighbors
maybe_gossip_for_neighbor(State = #state{unfilled_active_set_count = Count, active_view = ActiveView})
    when Count rem 7 == 0 andalso Count > 3 ->
  lager:debug("Gossiping for neighbor"),
  ActiveViewSize = length(ActiveView),
  Payload = #{message => unfilled_active_view, active_view_size => ActiveViewSize, node => node()},
  GossipMessage = wrap_gossip_message(Payload, State),
  do_randomized_gossip(GossipMessage, ActiveView),
  State;

maybe_gossip_for_neighbor(State) ->
  State.

wrap_gossip_message(Message = #{message := MessageType}, State) ->
  Metadata = new_metadata(MessageType, State),
  #{message => gossip, path => [], payload => Message, metadata => Metadata}.


do_randomized_gossip(_GossipMessage = #{path := Path}, _ActiveView) when length(Path) > 10 ->
  %% Drop the message after it's seen 10 nodes
  ok;
do_randomized_gossip(GossipMessage = #{path := Path}, ActiveView) ->
  NewPath = [node()|Path],
  GossipMessage1 = GossipMessage#{path := NewPath},
  Candidates = ActiveView -- NewPath,
  case Candidates of
    [] ->
      %% Drop message
      ok;
    Candidates1 ->
      %% TODO:
      %% Determine if we should narrow the gossip at all
      %% The code for doing that is below:begin
      % Candidates2 = shuffle_list(Candidates1, seed()),
      % {RealCandidates, _} = lists:split(2, Candidates2),
      lists:foreach(fun(Candidate) -> gossip_to(Candidate, GossipMessage1) end, Candidates1)
  end.
gossip_to(Candidate, GossipMessage = #{path := Path}) ->
  case lists:member(Candidate, Path) of
    true ->
      ok;
    false ->
      gen_server:cast({?SERVER, Candidate}, GossipMessage)
  end.
handle_gossip_message(GossipMessage = #{payload := Payload, metadata := Metadata}, State = #state{active_view = ActiveView, messages = Messages}) ->
  case seen_message(Metadata, Messages) of
    true ->
      Messages1 = recognize_message(Metadata, Messages),
      State#state{messages = Messages1};
    false ->
      do_randomized_gossip(GossipMessage, ActiveView),
      Messages1 = recognize_message(Metadata, Messages),
      State1 = State#state{messages = Messages1},
      State2 = handle_gossip_payload(Payload, State1),
      State2
  end.

%% Gossip handlers -
%% These will mostly be internal messages
%% But we'll be able to send external gossip messages as well
%
handle_gossip_payload(#{message := unfilled_active_view}, State = #state{active_view = MyActiveView})
    when length(MyActiveView) >= ?ACTIVE_VIEW_SIZE ->
  State;

handle_gossip_payload(#{message := unfilled_active_view, node := RemoteNode},
  State) ->
  send_neighbor_to(5000, RemoteNode, low),
  State.

check_state(State = #state{passive_view = PassiveView, active_view = ActiveView, monitors = Monitors}) ->
  case ordsets:intersection(PassiveView, ActiveView) of
    [] ->
      ok;
    Else ->
      error({overlapping, Else})
  end,
  case ordsets:is_element(node(), ActiveView) of
    true ->
      error(self_in_active_view);
    _ -> ok
  end,
  case ordsets:is_element(node(), PassiveView) of
    true ->
      error(self_in_passive_view);
    _ -> ok
  end,
  %% Ensure we have a monitor_ref for every node in ActiveView
  CheckFun1 =
    fun(Node) ->
      case node_to_monitor_ref(Node, Monitors) of
        false ->
          lager:error("Node ~p lacks of a monitor reference: ~p", [Node, Monitors]),
          error({no_monitor_ref, Node});
        Ref when is_reference(Ref) ->
          ok
      end
    end,
  lists:foreach(CheckFun1, ActiveView),
  %% Ensure there aren't duplicate monitor refs
  MonitoredNodes = [Monitor#monitor.node || Monitor <- Monitors],
  SortedMonitoredNodes = lists:sort(MonitoredNodes),
  MonitoredNodesSet = ordsets:from_list(MonitoredNodes),
  case MonitoredNodesSet of
    SortedMonitoredNodes ->
      ok;
    _Other ->
      lager:error("Duplicate monitored nodes: ~p", [MonitoredNodes]),
      error(duplicate_monitored_nodes)
  end,
  %% Ensure there aren't excess monitors
  case MonitoredNodesSet == ActiveView of
    true ->
      ok;
    false ->
      error(mistmatched_monitors)
  end,
  State.

contact_nodes(_State = #state{extra_masters = ExtraMasters}) ->
  contact_nodes(ExtraMasters);
contact_nodes(ExtraMasters) ->
  ContactNodes = ordsets:from_list(lashup_config:contact_nodes()),
  AllMasters = ordsets:union(ContactNodes, ExtraMasters),
  ordsets:del_element(node(), AllMasters).



handle_shuffle(Shuffle = #{ttl := 0}, State) ->
  do_shuffle(Shuffle, State);
handle_shuffle(Shuffle = #{node := Node, sender := Sender, ttl := TTL}, State = #state{active_view = ActiveView})
    when Sender =/= node() andalso Node =/= node()->
  PotentialNodes = ordsets:del_element(Node, ActiveView),
  PotentialNodes1 = ordsets:del_element(Sender, PotentialNodes),
  case PotentialNodes1 of
    [] ->
      lager:warning("Handling shuffle early, because no nodes to send it to"),
      do_shuffle(Shuffle, State);
    Else ->
      NewShuffle = Shuffle#{sender := node(), ttl := TTL - 1},
      NextNode = choose_node(Else),
      gen_server:cast({?SERVER, NextNode}, NewShuffle),
      State
  end.
do_shuffle(_Shuffle = #{active_view := RemoteActiveView, passive_view := RemotePassiveView, node := Node},
    State = #state{passive_view = MyPassiveView, active_view = MyActiveView}) ->
  ReplyNodes1 = ordsets:subtract(MyPassiveView, RemoteActiveView),
  ReplyNodes2 = ordsets:subtract(ReplyNodes1, RemotePassiveView),
  ShuffleReply = #{message => shuffle_reply, node => node(), combined_view => ReplyNodes2},
  gen_server:cast({?SERVER, Node}, ShuffleReply),
  schedule_disconnect(Node),

  LargeCombinedView = ordsets:union([MyPassiveView, RemoteActiveView, RemotePassiveView]),
  LargeCombinedView1 = ordsets:subtract(LargeCombinedView, MyActiveView),
  LargeCombinedView2 = ordsets:del_element(node(), LargeCombinedView1),
  {CombinedView, _} = trim_ordset_to(LargeCombinedView2, ?PASSIVE_VIEW_SIZE),
  State#state{passive_view = CombinedView}.



%% It returns how long to wait until to shuffle again
try_shuffle(_State = #state{active_view = []}) ->
  lager:warning("Could not shuffle because active view empty"),
  10000;
try_shuffle(_State = #state{active_view = ActiveView, passive_view = PassiveView}) ->
  %% TODO:
  %% -Make TTL Configurable
  %% -Allow for limiting view sizes further
  Shuffle = #{message => shuffle, sender => node(), node => node(), active_view => ActiveView, passive_view => PassiveView, ttl => 5},
  Node = choose_node(ActiveView),
  gen_server:cast({?SERVER, Node}, Shuffle),
  case length(PassiveView) of
    Size when Size < 0.5 * ?PASSIVE_VIEW_SIZE ->
      5000;
    _ ->
      60000
  end.


handle_shuffle_reply(_ShuffleReply = #{combined_view := CombinedView}, State = #state{passive_view = MyPassiveView, active_view = MyActiveView}) ->
  LargeCombinedView = ordsets:union(CombinedView, MyPassiveView),
  LargeCombinedView1 = ordsets:subtract(LargeCombinedView, MyActiveView),
  LargeCombinedView2 = ordsets:del_element(node(), LargeCombinedView1),
  {NewPassiveView, _} = trim_ordset_to(LargeCombinedView2, ?PASSIVE_VIEW_SIZE),
  State#state{passive_view = NewPassiveView}.

ensure_monitor(Node, Monitors) ->
  case has_monitor(Node, Monitors) of
    false ->
      MonitorRef = monitor(process, {?SERVER, Node}),
      true = is_reference(MonitorRef),
      Monitor = #monitor{node = Node, monitor_ref = MonitorRef},
      lists:keystore(Node, #monitor.node, Monitors, Monitor);
    true ->
      Monitors
  end.

remove_monitor(MonitorRef, Monitors) when is_reference(MonitorRef) andalso is_list(Monitors) ->
  demonitor(MonitorRef),
  lists:keydelete(MonitorRef, #monitor.monitor_ref, Monitors);
remove_monitor(Node, Monitors) when is_atom(Node) andalso is_list(Monitors) ->
  case node_to_monitor_ref(Node, Monitors) of
    false ->
      Monitors;
    MonitorRef ->
      demonitor(MonitorRef),
      lists:keydelete(MonitorRef, #monitor.monitor_ref, Monitors)
  end.
node_to_monitor_ref(Node, Monitors) ->
  case lists:keyfind(Node, #monitor.node, Monitors) of
    false ->
      false;
    Monitor ->
      Monitor#monitor.monitor_ref
  end.

monitor_ref_to_node(Node, Monitors) ->
  case lists:keyfind(Node, #monitor.monitor_ref, Monitors) of
    false ->
      false;
    Monitor ->
      Monitor#monitor.node
  end.


has_monitor(Node, Monitors) ->
  lists:keymember(Node, #monitor.node, Monitors).

shuffle_list(List, FixedSeed) ->
  {_, PrefixedList} =
  lists:foldl(fun(X, {SeedState, Acc}) ->
    {N, SeedState1} = random:uniform_s(1000000, SeedState),
    {SeedState1, [{N, X}|Acc]}
    end,
    {FixedSeed, []},
    List),
  PrefixedListSorted = lists:sort(PrefixedList),
  [Value || {_N, Value} <- PrefixedListSorted].


push_state(#state{passive_view = PV, active_view = AV}) ->
  gen_event:sync_notify(lashup_hyparview_events, #{type => view_update, active_view => AV, passive_view => PV}).

seed() ->
  {erlang:phash2([node()]),
    erlang:monotonic_time(),
    erlang:unique_integer()}.

new_metadata(MessageType, _State = #state{init_time = InitTime}) ->
  {{node(), InitTime, MessageType}, erlang:unique_integer([monotonic])}.

%% Limit to 10000 messages
recognize_message(Metadata, Messages) when length(Messages) > 10000 ->
  recognize_message(Metadata, lists:split(10000, Messages));

recognize_message(_Metadata = {Key = {_Node, _InitTime, _MessageType}, Counter}, Messages) ->
  case lists:keyfind(Key, 1, Messages) of
    false ->
      [{Key, Counter}|Messages];
    Tuple = {_Key, OldCounter} when Counter > OldCounter ->
      Messages1 = lists:delete(Tuple, Messages),
      [{Key, Counter}|Messages1];
    %% Move the tuple up, since we saw it again
    Tuple ->
      Messages1 = lists:delete(Tuple, Messages),
      [Tuple|Messages1]
  end.

seen_message(_Metadata = {Key = {_Node, _InitTime, _MessageType}, Counter}, Messages) ->
  case lists:keyfind(Key, 1, Messages) of
    false ->
      false;
    _Tuple = {_Key, OldCounter} when Counter > OldCounter ->
      false;
    _Tuple ->
      true
  end.

shuffle_backoff_loop(Delay, Pid) ->
  timer:sleep(Delay),
  case catch gen_server:call(?SERVER, try_shuffle) of
    Backoff when is_integer(Backoff) ->
      shuffle_backoff_loop(Backoff, Pid);
    _ ->
      shuffle_backoff_loop(Delay, Pid)
  end.

handle_do_probe(Node, State = #state{active_view = ActiveViews, pings_in_flight = PIF}) ->
  case lists:member(Node, ActiveViews) of
    true ->
      Now = erlang:monotonic_time(),
      {ok, TimerRef} = timer:send_after(100, {ping_failed, Node}),
      gen_server:cast({?SERVER, Node}, #{message => ping, from => self(), now => Now, ref => TimerRef}),
      PIF2 = orddict:store(TimerRef, Node, PIF),
      State#state{pings_in_flight = PIF2};
    false ->
      State
  end.

handle_ping_rq(State = #state{active_view = ActiveViews}) when ActiveViews == [] ->
  reschedule_ping(),
  State;
handle_ping_rq(State = #state{active_view = ActiveViews, ping_idx = PingIdx, pings_in_flight = PIF}) ->
  reschedule_ping(),
  Idx = PingIdx rem length(ActiveViews) + 1,
  Node = lists:nth(Idx, ActiveViews),
  Now = erlang:monotonic_time(),
  {ok, TimerRef} = timer:send_after(100, {ping_failed, Node}),
  gen_server:cast({?SERVER, Node}, #{message => ping, from => self(), now => Now, ref => TimerRef}),
  PIF2 = orddict:store(TimerRef, Node, PIF),
  State#state{pings_in_flight = PIF2, ping_idx = PingIdx + 1}.


handle_ping(PingMessage = #{from := From}, _State) ->
  PongMessage = PingMessage#{message => pong},
  gen_server:cast(From, PongMessage).

%% TODO: Keep track of RTTs somewhere
handle_pong(_PongMessage = #{ref := Ref}, State = #state{pings_in_flight = PIF}) ->
  timer:cancel(Ref),
  PIF2 = orddict:erase(Ref, PIF),
  State#state{pings_in_flight = PIF2}.

%% TODO: Determine whether we should disconnect_node
%% Or do something more 'clever'
handle_ping_failed(Node, State) ->
  lager:info("Ping failed for node: ~p", [Node]),
  erlang:disconnect_node(Node),
  State.


schedule_disconnect(Node) ->
  timer:send_after(25000, {maybe_disconnect, Node}).

handle_maybe_disconnect(Node, State = #state{active_view = ActiveView}) ->
  case {lists:member(Node, nodes()), lists:member(Node, ActiveView)} of
    {true, false} ->
      erlang:disconnect_node(Node),
      State;
    _Else ->
      State
  end.

poll_for_master_nodes() ->
  case catch lashup_utils:maybe_poll_for_master_nodes() of
    List when is_list(List) andalso length(List) > 0 ->
      gen_server:cast(?SERVER, {masters, List});
    _ ->
      ok
  end.


-ifdef(TEST).
trim_test() ->
  Ordset = ordsets:from_list([1,3,4,5]),
  {Ordset1, _} = trim_ordset_to(Ordset, 3),
  ?assertEqual(3, length(Ordset1)).
-endif.




