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
  poll_for_master_nodes/0,
  do_probe/1,
  ping_failed/1,
  recognize_pong/1,
  recommend_neighbor/1
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

-record(monitor, {monitor_ref :: reference(), node :: node()}).

-type monitor() :: #monitor{}.

-record(state, {
  active_view = ordsets:new() :: ordsets:ordset(),
  passive_view = ordsets:new() :: ordsets:ordset(),
  monitors = [] :: [monitor()],
  fixed_seed :: rand:state(),
  idx = 1 :: pos_integer(),
  unfilled_active_set_count = 0, %% Number of times I've tried to neighbor and I've not seen an active set
  init_time = erlang:error(init_time_unset) :: integer(),
  messages = [],
  join_window,
  ping_idx = 1 :: pos_integer(),
  joined = false :: boolean(),
  extra_masters = [] :: [node()]
}).

-type state() :: state().

%% TODO: Make map types better defined
%% We probably want to define a partial of the map

-type join_success() :: map().
-type join() :: map().
-type join_deny() :: map().
-type forward_join() :: map().
-type disconnect() :: map().
-type neighbor() :: map().
-type neighbor_deny() :: map().
-type neighbor_accept() :: map().
-type shuffle() :: map().
-type shuffle_reply() :: map().
-type hyparview_message() :: join_success() | join() | forward_join() | disconnect() | neighbor() | neighbor_deny() |
                             neighbor_accept() | shuffle() | shuffle_reply() | join_deny().

%%%===================================================================
%%% API
%%%===================================================================

%% The recognize ping function tells the hyparview membership server that
%% this node has us in their active view
recognize_pong(Pong) ->
  gen_server:cast(?SERVER, {recognize_pong, Pong}).

%% This is a way for lashup_gm_probe to recommend a neighbor
%% if it finds a neighbor that's outside of our reachability graph
recommend_neighbor(Node) ->
  gen_server:cast(?SERVER, {recommend_neighbor, Node}).

%% Pings the node immediately.
do_probe(Node) ->
  gen_server:cast(?SERVER, {do_probe, Node}).

ping_failed(Node) ->
  gen_server:cast(?SERVER, {ping_failed, Node}).

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
  {ok, State :: state()} | {ok, State :: state(), timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  rand:seed(exsplus),
  %% This seed is a fixed seed used for shuffling the list
  FixedSeed = lashup_utils:seed(),
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

  %% Only poll every 5 minutes beyond that
  {ok, _} = timer:apply_interval(300000, ?MODULE, poll_for_master_nodes, []),
  State = #state{passive_view = contact_nodes([]),
    fixed_seed = FixedSeed, init_time = erlang:system_time(), join_window = Window},
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
handle_call(stop, _From, State) ->
  {stop, normal, State};
handle_call({do_connect, Node}, _From, State) when is_atom(Node) ->
  send_neighbor_to(5000, Node, high),
  {reply, ok, State};
handle_call(get_active_view, _From, State = #state{active_view = ActiveView}) ->
  {reply, ActiveView, State};
handle_call(get_passive_view, _From, State = #state{passive_view = PassiveView}) ->
  {reply, PassiveView, State};
handle_call(try_shuffle, _From, State) ->
  NewDelay = try_shuffle(State),
  {reply, NewDelay, State}.

%% No handler here, because no one should ever call us off-node, and it's indicative of a bug

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
%% We generated a timer (with a ref) when we did the join with a timeout
%% We get passed back that ref, and now we need to delete it
handle_cast({do_probe, Node}, State) ->
  State1 = handle_do_probe(Node, State),
  {noreply, check_state(State1)};
handle_cast(Message = #{message := _}, State) ->
  State1 = handle_message_cast(Message, State),
  {noreply, State1};
handle_cast({recognize_pong, Pong}, State) ->
  handle_recognize_pong(Pong, State),
  {noreply, State};
handle_cast({ping_failed, Node}, State) ->
  State1 = handle_ping_failed(Node, State),
  push_state(State1),
  {noreply, check_state(State1)};
handle_cast({masters, List}, State) ->
  MasterSet = ordsets:del_element(node(), List),
  State1 = State#state{extra_masters = MasterSet},
  {noreply, check_state(State1)};
handle_cast({recommend_neighbor, Node}, State) ->
  handle_recommend_neighbor(Node, State),
  {noreply, State};
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
-spec(handle_info(Info :: timeout() | term(), State :: state()) ->
  {noreply, NewState :: state()} |
  {noreply, NewState :: state(), timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: state()}).
%% It's likely just that someone connected to us, and that's okay
handle_info(DownMessage = {'DOWN', _, _, _, _}, State) ->
  State1 = handle_down_message(DownMessage, State),
  push_state(State1),
  {noreply, check_state(State1)};
%% We don't need a full active view
%% In fact, the network can get into (healthy) cases where it's not possible
%% Like running fewer than the active view size count nodes
%% So, only neighbor if more than 25% of our active view is open.
handle_info(maybe_neighbor, State = #state{active_view = ActiveView}) when length(
  ActiveView) >= ?ACTIVE_VIEW_SIZE * 0.75 ->
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
  State :: state()) -> term()).
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
-spec(code_change(OldVsn :: term() | {down, term()}, State :: state(),
  Extra :: term()) ->
  {ok, NewState :: state()} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%% Message Dispatch functions

-spec(handle_message_cast(hyparview_message(), State :: state()) -> state()).
handle_message_cast(JoinSuccess = #{message := join_success}, State) ->
  check_state(handle_join_success(JoinSuccess, State));
handle_message_cast(JoinDeny = #{message := join_deny}, State) ->
  check_state(handle_join_deny(JoinDeny, State));
handle_message_cast(_Join = #{message := join, sender := Node, ref := Ref}, State) ->
  check_state(handle_join(Node, State, Ref));
handle_message_cast(ForwardJoin = #{message := forward_join}, State) ->
  State1 = handle_forward_join(ForwardJoin, State),
  push_state(State1),
  check_state(State1);
handle_message_cast(Disconnect = #{message := disconnect}, State) ->
  State1 = handle_disconnect(Disconnect, State),
  push_state(State1),
  check_state(State1);
handle_message_cast(Neighbor = #{message := neighbor}, State) ->
  State1 = handle_neighbor(Neighbor, State),
  push_state(State1),
  check_state(State1);
handle_message_cast(NeighborDeny = #{message := neighbor_deny}, State) ->
  check_state(handle_neighbor_deny(NeighborDeny, State));
handle_message_cast(NeighborAccept = #{message := neighbor_accept}, State) ->
  check_state(handle_neighbor_accept(NeighborAccept, State));
handle_message_cast(Shuffle = #{message := shuffle}, State) ->
  check_state(handle_shuffle(Shuffle, State));
handle_message_cast(ShuffleReply = #{message := shuffle_reply}, State) ->
  check_state(handle_shuffle_reply(ShuffleReply, State));
handle_message_cast(UnknownMessage, State) ->
  lager:warning("Received unknown lashup message: ~p", [UnknownMessage]),
  State.

%% RESCHEDULING Functions
%% Ping every one of my neighbors at least every second
reschedule_ping() ->
  reschedule_ping(100).
reschedule_ping(Time) ->
  RandFloat = rand:uniform(),
  Multipler = 1 + round(RandFloat),
  Delay = Multipler * Time,
  timer:send_after(Delay, ping_rq).

reschedule_maybe_neighbor() ->
  reschedule_maybe_neighbor(?NEIGHBOR_INTERVAL).
reschedule_maybe_neighbor(Time) ->
  RandFloat = rand:uniform(),
  Multipler = 1 + round(RandFloat),
  Delay = Multipler * Time,
  timer:send_after(Delay, maybe_neighbor).

reschedule_join() ->
  reschedule_join(?JOIN_INTERVAL).
reschedule_join(BaseTime) ->
  RandFloat = rand:uniform(),
  Multipler = 1 + round(RandFloat),
  timer:send_after(Multipler * BaseTime, try_join).

%%% Rescheduling functions


choose_node(Nodes) when length(Nodes) > 0 ->
  Length = erlang:length(Nodes),
  NodeIdx = rand:uniform(Length),
  lists:nth(NodeIdx, Nodes).

%% JOIN CODE
-spec try_do_join(State :: state()) -> error | ok.
try_do_join(State) ->
  case do_join(State) of
    ok ->
      ok;
    _ ->
      reschedule_join(),
      error
  end.

-spec(do_join(State :: state()) -> ok | {error, Reason :: term()}).
do_join(State) ->
  ContactNodes = contact_nodes(State),
  case ContactNodes of
    [] ->
      {error, no_contact_nodes};
    _ ->
      Node = choose_node(ContactNodes),
      try_connect_then_join(Node)
  end.

-spec(try_connect_then_join(node()) -> ok | {error, Reason :: term()}).
try_connect_then_join(Node) ->
  Timeout = lashup_config:join_timeout(),
  case ping_with_timeout(Node, Timeout) of
    pong ->
      join(Node);
    %% This is the timeout case
    maybe_pong ->
      join(Node);
    _ ->
      {error, could_not_connect}
  end.

-spec(ping_with_timeout(Node :: node(), Timeout:: non_neg_integer()) -> ok | maybe_pong | pong | pang).
ping_with_timeout(Node, Timeout) ->
  Ref = make_ref(),
  Self = self(),
  spawn_link(fun() -> Self ! {Ref, net_adm:ping(Node)} end),
  receive
    {Ref, Response} ->
      Response
  after Timeout ->
    maybe_pong
  end.



-spec(join(node()) -> ok).
join(Node) ->
  {ok, Ref} = timer:send_after(1000, join_failed),
  gen_server:cast({?SERVER, Node}, #{message => join, sender => node(), ref => Ref}).


%% This is ridiculously inefficient on the order of O(N!),
%% but I'm prototyping
%% And this input shouldn't get much bigger than 30.


-spec(trim_ordset_to(ordsets:ordset(), non_neg_integer()) -> {ordsets:ordset(), ordsets:ordset()}).

trim_ordset_to(Ordset, Size) when Size > 0 ->
  trim_ordset_to(Ordset, Size, []).

trim_ordset_to(Ordset, Size, DroppedItems) when length(Ordset) > Size ->
  Idx = rand:uniform(length(Ordset)),
  ItemToRemove = lists:nth(Idx, Ordset),
  Ordset1 = ordsets:del_element(ItemToRemove, Ordset),
  DroppedItems1 = ordsets:add_element(ItemToRemove, DroppedItems),
  trim_ordset_to(Ordset1, Size, DroppedItems1);
trim_ordset_to(Ordset, _Size, DroppedItems) ->
  {Ordset, DroppedItems}.


-spec(handle_join(Node :: node(), State :: state(), Ref :: reference()) -> state()).
handle_join(Node, State = #state{join_window = JoinWindow, active_view = ActiveView}, Ref)
  when Node =/= node() ->
  lager:debug("Saw join from ~p", [Node]),
  State1 =
  case lashup_utils:count_ticks(JoinWindow) of
    %% Limit it to 25 joins/sec if the active view is full
    Num when length(ActiveView) == ?ACTIVE_VIEW_SIZE andalso Num < 25 ->
      really_handle_join(Node, State, Ref);
    %% If the active view is less than that, throttle to 1 / sec
    Num when Num < 1 ->
      really_handle_join(Node, State, Ref);
    %% Else, drop it
    WindowSize ->
      lager:warning("Throttling joins, window size: ~p, active view size: ~p", [WindowSize, length(ActiveView)]),
      deny_join(State, Node, Ref),
      State
  end,
  push_state(State1),
  State1;

handle_join(_, State, _) -> State.

-spec(deny_join(State :: state(), Node :: node(), Ref :: reference()) -> ok).
deny_join(_State = #state{active_view = ActiveView}, Node, Ref) ->
  Reply = #{message => join_deny, sender => node(), ref => Ref, active_view => ActiveView},
  gen_server:cast({?SERVER, Node}, Reply).


  -spec(really_handle_join(Node :: node(), State :: state(), Ref :: reference()) -> state()).
really_handle_join(Node, State = #state{join_window = JoinWindow}, Ref) ->
  case try_add_node_to_active_view(Node, State) of
    {ok, NewState = #state{active_view = ActiveView, passive_view = PassiveView}} ->
      ARWL = lashup_config:arwl(),
      Fanout = ordsets:del_element(Node, ActiveView),
      ForwardJoinMessage = #{message => forward_join, node => Node, ttl => ARWL, sender => node(), seen => [node()]},
      gen_server:abcast(Fanout, ?SERVER, ForwardJoinMessage),
      Reply = #{message => join_success, sender => node(), ref => Ref, passive_view => PassiveView},
      gen_server:cast({?SERVER, Node}, Reply),
      JoinWindow1 = lashup_utils:add_tick(JoinWindow),
      NewState#state{join_window = JoinWindow1};
    {error, NewState} ->
      NewState
  end.

-spec(handle_join_deny(join_deny(), state()) -> state()).
handle_join_deny(_JoinDeny =  #{message := join_deny, sender := Sender, ref := Ref, active_view := RemoteActiveView},
    State = #state{active_view = []})->
  ContactNodes = contact_nodes(State),
  ProhibitedNodes = ordsets:add_element(Sender, ContactNodes),
  case ordsets:subtract(RemoteActiveView, ProhibitedNodes) of
    [] ->
      State;
    RemoteActiveView1 ->
      timer:cancel(Ref),
      Node = choose_node(RemoteActiveView1),
      join(Node),
      State
  end;
handle_join_deny(_JoinDeny, State) ->
  State.

-spec(handle_join_success(join_success(), state()) -> state()).
handle_join_success(_JoinSuccess =
  #{message := join_success, sender := Sender, ref := Ref, passive_view := RemotePassiveView}, State) ->
  timer:cancel(Ref),
  State1 = lists:foldl(fun maybe_add_node_passive_view/2, State, RemotePassiveView),
  State3 =
  case try_add_node_to_active_view(Sender, State1) of
    {ok, State2} ->
      State2#state{joined = true};
    {error, State2} ->
      State2
  end,
  push_state(State3),
  State3.

-spec(trim_active_view(Size :: non_neg_integer(), State :: state()) -> state()).
trim_active_view(Size, State = #state{active_view = ActiveView}) ->
  {_, DroppedNodes} = trim_ordset_to(ActiveView, Size),
  State1 = lists:foldl(fun disconnect_node/2, State, DroppedNodes),
  case DroppedNodes of
    [] ->
      ok;
    _ ->
      lager:debug("Removing ~p from active view", [DroppedNodes])
  end,
  State1.

-spec(try_add_node_to_active_view(node(), state()) -> {ok, state()} | {error, state()}).
try_add_node_to_active_view(Node, State) when Node =/= node() ->
  %% There is one critical component here -
  %% We have to return a non-error code once we decide to trim from the active view
  %% If we don't, it could end with an asymmetrical graph
  case net_kernel:connect_node(Node) of
    true ->
      State1 = trim_active_view(?ACTIVE_VIEW_SIZE - 1, State),
      Monitors1 = State1#state.monitors,
      ActiveView1 = State1#state.active_view,
      PassiveView1 = State1#state.passive_view,
      Monitors2 = ensure_monitor(Node, Monitors1),
      ActiveView2 = ordsets:add_element(Node, ActiveView1),
      PassiveView2 = ordsets:del_element(Node, PassiveView1),
      State2 = State1#state{active_view = ActiveView2, passive_view = PassiveView2, monitors = Monitors2},
      {ok, State2};
    _ ->
      lager:warning("Received join from node ~p, but could not connect back to it", [Node]),
      {error, State}
  end;

try_add_node_to_active_view(_Node, State) ->
  {error, State}.

maybe_add_node_passive_view(Node, State = #state{active_view = ActiveView, passive_view = PassiveView})
    when Node =/= node() ->
  {ActiveViewNew, PassiveViewNew} = case {ordsets:is_element(Node, ActiveView), ordsets:is_element(Node,
    PassiveView)} of
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
  {_, State1} = try_add_node_to_active_view(Node, State),
  State1;
handle_forward_join(_ForwardJoin = #{node := Node}, State = #state{active_view = []}) ->
  {_, State1} = try_add_node_to_active_view(Node, State),
  State1;
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

forward_forward_join(ForwardJoin = #{ttl := TTL, node := Node, seen := Seen},
    #state{active_view = ActiveView}) ->
  Seen1 = ordsets:add_element(node(), Seen),
  ForwardJoin1 = ForwardJoin#{ttl => TTL - 1, sender := node(), seen := Seen1},
  case ordsets:subtract(ActiveView, Seen) of
    [] ->
      lager:warning("Forwarding join original node ~p dropped", [Node]);
    Nodes ->
      forward_forward_join1(ForwardJoin1, Nodes)
  end;
forward_forward_join(ForwardJoin = #{ttl := TTL, sender := Sender, node := Node}, #state{active_view = ActiveView}) ->
  ForwardJoin1 = ForwardJoin#{ttl => TTL - 1, sender := node()},
  case ordsets:del_element(Sender, ActiveView) of
    [] ->
      lager:warning("Forwarding join original node ~p dropped", [Node]);
    Nodes ->
      forward_forward_join1(ForwardJoin1, Nodes)
  end.

forward_forward_join1(ForwardJoin, Nodes) when is_list(Nodes) ->
  Idx = rand:uniform(length(Nodes)),
  TargetNode = lists:nth(Idx, Nodes),
  gen_server:cast({?SERVER, TargetNode}, ForwardJoin).


%% TODO:
%% Maybe we should disconnect from the node at this point?
%% I'm unsure, because if another service is using hyparview for peer sampling
%% We could break the TCP connection before it's ready
-spec(handle_disconnect(disconnect(), state()) -> state()).
handle_disconnect(_Disconnect = #{sender := Sender},
    State = #state{active_view = ActiveView, passive_view = PassiveView, monitors = Monitors}) ->
  lager:info("Node ~p received disconnect from ~p", [node(), Sender]),
  MonitorRef = node_to_monitor_ref(Sender, Monitors),
  Monitors1 = remove_monitor(MonitorRef, Monitors),
  ActiveView1 = ordsets:del_element(Sender, ActiveView),
  PassiveView1 = ordsets:add_element(Sender, PassiveView),
  schedule_disconnect(Sender),
  State#state{active_view = ActiveView1, passive_view = PassiveView1, monitors = Monitors1}.


handle_down_message(_DownMessage = {'DOWN', MonitorRef, process, _Info, Reason},
    State = #state{active_view = ActiveView, passive_view = PassiveView, monitors = Monitors}) ->
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
maybe_neighbor(State = #state{fixed_seed = FixedSeed, idx = Idx, unfilled_active_set_count = Count}) ->
  case {State#state.active_view, State#state.passive_view} of
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
    {ActiveView, []} ->
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
      maybe_gm_neighbor(2000, State),
      send_neighbor(2000, PassiveView, low, Idx, FixedSeed),
      State#state{idx = Idx + 1, unfilled_active_set_count = Count + 1}
  end.

%% Timeout is actually a minimum time
maybe_gm_neighbor(Timeout, _State = #state{unfilled_active_set_count = Count})
  when Count rem 5 == 0 andalso Count > 3 ->
  %% This is to ensure that there isn't a dependency loop between us and gm
  case catch lashup_gm:get_neighbor_recommendations(?ACTIVE_VIEW_SIZE) of
    {ok, Node} ->
      lager:info("Get Neighbors Successful: ~p", [Node]),
      send_neighbor_to(Timeout, Node, low),
      Node;
    Error ->
      lager:info("Get Neighbors Unsuccessful: ~p", [Error]),
      ok
  end;
maybe_gm_neighbor(_Timeout, _State) ->
  ok.

send_neighbor(Timeout, PassiveView, Priority, Idx, FixedSeed) when length(PassiveView) > 0 ->
  ShuffledPassiveView = lashup_utils:shuffle_list(PassiveView, FixedSeed),
  RealIdx = Idx rem length(ShuffledPassiveView) + 1,
  Node = lists:nth(RealIdx, ShuffledPassiveView),
  send_neighbor_to(Timeout, Node, Priority),
  Node.

-spec(send_neighbor_to(Timeout :: non_neg_integer(), Node :: node(), Priority :: high | low) -> ok).
send_neighbor_to(Timeout, Node, Priority) when is_integer(Timeout) ->
  lager:debug("Sending neighbor to: ~p", [Node]),
  Ref = timer:send_after(Timeout * 3, {tried_neighbor, Node}),
  gen_server:cast({?SERVER, Node}, #{message => neighbor, ref => Ref, priority => Priority, sender => node()}).

-spec(handle_neighbor(neighbor(), state()) -> state()).
handle_neighbor(_Neighbor = #{priority := low, sender := Sender, ref := Ref}, State = #state{active_view = ActiveView})
  when length(ActiveView) == ?ACTIVE_VIEW_SIZE ->
  %% The Active neighbor list is full
  lager:info("Denied neighbor request from ~p because active view full", [Sender]),
  PassiveView = State#state.passive_view,
  gen_server:cast({?SERVER, Sender},
    #{message => neighbor_deny, sender => node(), ref => Ref, passive_view => PassiveView}),
  State;

%% Either this is a high priority request
%% Or I have an empty slot in my active view list
handle_neighbor(_Neighbor = #{sender := Sender, ref := Ref}, State) ->
  case try_add_node_to_active_view(Sender, State) of
    {ok, NewState} ->
      gen_server:cast({?SERVER, Sender}, #{message => neighbor_accept, sender => node(), ref => Ref}),
      NewState;
    {error, NewState = #state{passive_view = PassiveView}} ->
      lager:warning("Failed to add neighbor ~p to active view on neighbor message", [Sender]),
      NeighborDeny = #{message => neighbor_deny, sender => node(), ref => Ref, passive_view => PassiveView},
      gen_server:cast({?SERVER, Sender}, NeighborDeny),
      NewState
  end.

-spec(handle_neighbor_accept(neighbor_accept(), state()) -> state()).
handle_neighbor_accept(_NeighborAccept = #{message := neighbor_accept, sender := Sender, ref := Ref}, State) ->
  timer:cancel(Ref),
  {_, State1} = try_add_node_to_active_view(Sender, State),
  push_state(State1),
  State1.

-spec(handle_neighbor_deny(neighbor_deny(), state()) -> state()).
handle_neighbor_deny(NeighborDeny = #{message := neighbor_deny, sender := Sender, ref := Ref}, State) ->
  timer:cancel(Ref),
  ActiveView = State#state.active_view,
  PassiveView = State#state.passive_view,
  lager:debug("Denied from joining ~p, while active view ~p, passive view: ~p", [Sender, ActiveView, PassiveView]),
  schedule_disconnect(Sender),
  State1 = neighbor_deny_combine_passive_view(NeighborDeny, State),
  push_state(State1),
  State1.

neighbor_deny_combine_passive_view(#{passive_view := RemotePassiveView}, State) ->
  PassiveView = State#state.passive_view,
  ActiveView = State#state.active_view,
  LargeCombinedView = ordsets:union(RemotePassiveView, PassiveView),
  LargeCombinedView1 = ordsets:subtract(LargeCombinedView, ActiveView),
  LargeCombinedView2 = ordsets:del_element(node(), LargeCombinedView1),
  {NewPassiveView, _} = trim_ordset_to(LargeCombinedView2, ?PASSIVE_VIEW_SIZE),
  State#state{passive_view = NewPassiveView};
neighbor_deny_combine_passive_view(_, State) ->
  State.

%% This is triggered by lashup_gm_probe to handle a permanently sectioned graph
%% We give it a one minute timeout, because there's no point in making it a small number.
%% We don't want to make it too high
-spec(handle_recommend_neighbor(Node :: node(), State :: state()) -> ok).
handle_recommend_neighbor(Node, _State) ->
  send_neighbor_to(60000, Node, high),
  ok.

%%%%%%%%%% End Neighbor management



%% Check State function is mostly there during testing
%% We should rip it out / disable it in prod
-spec(check_state(state()) -> state()).
check_state(State = #state{}) ->
  ok = check_views(State),
  ok = check_monitors(State),
  State.

-spec(check_monitors(state()) -> ok).
check_monitors(#state{active_view = ActiveView, monitors = Monitors}) ->
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
      error(mismatched_monitors)
  end,
  ok.

-spec(check_views(state()) -> ok).
check_views(_State = #state{active_view = ActiveView, passive_view = PassiveView}) ->
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
  ok.
%% End check_state
contact_nodes(_State = #state{extra_masters = ExtraMasters}) ->
  contact_nodes(ExtraMasters);
contact_nodes(ExtraMasters) ->
  ContactNodes = ordsets:from_list(lashup_config:contact_nodes()),
  AllMasters = ordsets:union(ContactNodes, ExtraMasters),
  ordsets:del_element(node(), AllMasters).



-spec(handle_shuffle(Shuffle :: shuffle(), state()) -> state()).
handle_shuffle(Shuffle = #{ttl := 0}, State) ->
  State1 = do_shuffle(Shuffle, State),
  push_state(State1),
  State1;
handle_shuffle(Shuffle = #{node := Node, sender := Sender, ttl := TTL}, State = #state{active_view = ActiveView})
  when Sender =/= node() andalso Node =/= node() ->
  PotentialNodes = ordsets:del_element(Node, ActiveView),
  PotentialNodes1 = ordsets:del_element(Sender, PotentialNodes),
  case PotentialNodes1 of
    [] ->
      lager:warning("Handling shuffle early, because no nodes to send it to"),
      State1 = do_shuffle(Shuffle, State),
      push_state(State1),
      State1;
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
  lager:info("Could not shuffle because active view empty"),
  10000;
try_shuffle(_State = #state{active_view = ActiveView, passive_view = PassiveView}) ->
  %% TODO:
  %% -Make TTL Configurable
  %% -Allow for limiting view sizes further
  Shuffle = #{
    message => shuffle,
    sender => node(),
    node => node(),
    active_view => ActiveView,
    passive_view => PassiveView,
    ttl => 5
  },
  Node = choose_node(ActiveView),
  gen_server:cast({?SERVER, Node}, Shuffle),
  case length(PassiveView) of
    Size when Size < 0.5 * ?PASSIVE_VIEW_SIZE ->
      5000;
    _ ->
      60000
  end.

-spec(handle_shuffle_reply(shuffle_reply(), state()) -> state()).
handle_shuffle_reply(_ShuffleReply = #{combined_view := CombinedView},
    State = #state{passive_view = MyPassiveView, active_view = MyActiveView}) ->
  LargeCombinedView = ordsets:union(CombinedView, MyPassiveView),
  LargeCombinedView1 = ordsets:subtract(LargeCombinedView, MyActiveView),
  LargeCombinedView2 = ordsets:del_element(node(), LargeCombinedView1),
  {NewPassiveView, _} = trim_ordset_to(LargeCombinedView2, ?PASSIVE_VIEW_SIZE),
  State1 = State#state{passive_view = NewPassiveView},
  push_state(State1),
  State1.

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


-spec(push_state(state()) -> ok).
push_state(#state{passive_view = PV, active_view = AV}) ->
  lashup_hyparview_events:ingest(AV, PV),
  ok.

shuffle_backoff_loop(Delay, Pid) ->
  timer:sleep(Delay),
  case catch gen_server:call(?SERVER, try_shuffle) of
    Backoff when is_integer(Backoff) ->
      shuffle_backoff_loop(Backoff, Pid);
    _ ->
      shuffle_backoff_loop(Delay, Pid)
  end.

handle_do_probe(Node, State = #state{active_view = ActiveViews}) ->
  case lists:member(Node, ActiveViews) of
    true ->
      lashup_hyparview_ping_handler:ping(Node),
      State;
    false ->
      State
  end.

handle_ping_rq(State = #state{active_view = ActiveViews}) when ActiveViews == [] ->
  reschedule_ping(),
  State;

handle_ping_rq(State = #state{active_view = ActiveViews, ping_idx = PingIdx}) ->
  reschedule_ping(),
  Idx = PingIdx rem length(ActiveViews) + 1,
  Node = lists:nth(Idx, ActiveViews),
  lashup_hyparview_ping_handler:ping(Node),
  State#state{ping_idx = PingIdx + 1}.

%% TODO: Determine whether we should disconnect_node
%% Or do something more 'clever'
-spec(handle_ping_failed(node(), state()) -> state()).
handle_ping_failed(Node, State) ->
  disconnect_node(Node, State).

%% Schedule two disconnects
%% The purpose of this is so that if we wrote some Erlang code that subscribes to the view
%% and doesn't only use erlang:send(..., [noconnect]), it'll result in reconnecting
%% This is fairly safe anyways, because we (try to) ensure that the node is not in our active view
%% when connecting

%% The only condition that this could be problematic is if there was something non-hyparview running
%% between the two nodes
%% TODO:
%% -Add a way to make connections exempt from disconnect
%% -Run a regular maintenance to make sure our connection count is small

%% The problem with lots of disterl connections is that:
%% (1) Net Ticks are awful, esp. if we get into a situation where we make a full mesh
%% (2) Run a regular maintenance and try to prune the nodes() in case something weird (tm) is happening
schedule_disconnect(Node) ->
  schedule_disconnect(Node, 25000),
  schedule_disconnect(Node, 50000).
schedule_disconnect(Node, Time) ->
  RandFloat = rand:uniform(),
  Multipler = 1 + round(RandFloat),
  Delay = Multipler * Time,
  timer:send_after(Delay, {maybe_disconnect, Node}).

-spec(disconnect_node(node(), state()) -> state()).
disconnect_node(Node, State = #state{monitors = Monitors, active_view = ActiveView, passive_view = PassiveView}) ->
  case lists:member(Node, ActiveView) of
    true ->
      Monitors1 = remove_monitor(Node, Monitors),
      DisconnectMessage = #{message => disconnect, sender => node()},
      case lists:member(Node, nodes()) of
        true ->
          gen_server:cast({?SERVER, Node}, DisconnectMessage);
        false ->
          ok
      end,
      PassiveView1 = ordsets:add_element(Node, PassiveView),
      ActiveView1 = ordsets:del_element(Node, ActiveView),
      schedule_disconnect(Node),
      State#state{active_view = ActiveView1, passive_view = PassiveView1, monitors = Monitors1};
    false ->
      State
  end.




handle_maybe_disconnect(Node, State) ->
  handle_maybe_disconnect1(Node, State).

%% Is this node part of exempt nodes?
handle_maybe_disconnect1(Node, State) ->
  ExemptNodes = application:get_env(lashup, exempt_nodes, []),
  case lists:member(Node, ExemptNodes) of
    true ->
      State;
    false ->
      handle_maybe_disconnect2(Node, State)
  end.

%% Is this node not part of my active view
handle_maybe_disconnect2(Node, State = #state{active_view = ActiveView}) ->
  case lists:member(Node, ActiveView) of
    true ->
      State;
    false ->
      handle_maybe_disconnect3(Node, State)
  end.

%% Is this node even connected?
handle_maybe_disconnect3(Node, State) ->
  case lists:member(Node, nodes()) of
    true ->
      erlang:disconnect_node(Node),
      State;
    false ->
      State
  end.

poll_for_master_nodes() ->
  case lashup_hyparview_membership:get_active_view() of
    [] ->
      really_poll_for_master_nodes();
    _ ->
      ok
  end.
really_poll_for_master_nodes() ->
  case catch lashup_utils:maybe_poll_for_master_nodes() of
    List when is_list(List) andalso length(List) > 0 ->
      gen_server:cast(?SERVER, {masters, List});
    _ ->
      ok
  end.

handle_recognize_pong(_Pong = #{now := _Now, receiving_node := Node},
  _State = #state{active_view = ActiveView, passive_view = PassiveView}) ->
  case {lists:member(Node, ActiveView), lists:member(Node, PassiveView)} of
    {true, false} ->
      %% TODO:
      %% Record successful roundtrip metric
      ok;
    {false, true} ->
      %% Something kinda weird has happened
      %% This can reasonably happen from late pongs
      %% TODO: Record it
      lager:info("Late Pong from Node: ~p, already moved to passive view", [Node]);
    {false, false} ->
      %% This is bad
      lager:warning("Pong from unknown node: ~p, not in active nor passive veiws", [Node])
  end.
  %% {true, true} should never happen. If it does, we _should_ crash.

-ifdef(TEST).
trim_test() ->
  Ordset = ordsets:from_list([1, 3, 4, 5]),
  {Ordset1, _} = trim_ordset_to(Ordset, 3),
  ?assertEqual(3, length(Ordset1)).
-endif.




