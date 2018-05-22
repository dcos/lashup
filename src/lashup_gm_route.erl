%%% @doc
%%% An LSA routing database (RIB) routing information base
%%% It has a cache that makes it suitable for a FIB
%%% @end
%%%
%%% TODO:
%%% -Determine whether it makes more sense to stash the graph in a sofs
%%% -Determine whether it makes sense to use sofs rather than maps to store the BFS trees

-module(lashup_gm_route).
-author("sdhillon").

-compile(inline).

-include_lib("stdlib/include/ms_transform.hrl").

-behaviour(gen_statem).

%% API
-export([
  start_link/0,
  update_node/2,
  delete_node/1,
  reachable/1,
  get_tree/1,
  get_tree/2,
  distance/2,
  reachable_nodes/1,
  unreachable_nodes/1,
  path_to/1,
  path_to/2,
  reverse_children/2,
  children/2,
  prune_tree/2,
  flush_events_helper/0
]).


-ifdef(TEST).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

-behaviour(proper_statem).

-export([proper/0]).
-export([
  initial_state/0,
  stop/0,
  command/1,
  precondition/2,
  postcondition/3,
  next_state/3,
  verify_routes/2
]).

-endif.

%% gen_statem callbacks
-export([init/1, terminate/3, code_change/4,
  callback_mode/0, handle_event/4]).

-record(state, {
  events = 0 :: non_neg_integer(),
  cache = #{} :: #{node() => tree()}
}).
-type state() :: state().

-type distance() :: non_neg_integer() | infinity.
-type tree() :: map().
-export_type([tree/0]).

%% Egress paths = active view
-record(vertex, {
  node = erlang:error() :: node(),
  dsts = ordsets:new() :: ordsets:ordset(node())
}).

-record(tree_entry, {
  parent = undefined :: node() | undefined,
  distance = infinity :: non_neg_integer() | infinity,
  children = ordsets:new() :: ordsets:ordset(node())
}).

%%%===================================================================
%%% API
%%%===================================================================

%% TODO:
%% -Add reachable by node
%% -Add reachable by IP


%% @doc
%% Persist or update a node
%% @end
-spec(update_node(Node :: node(), Dsts :: [node()]) -> ok).
update_node(Node, Dsts)  ->
  gen_statem:cast(?MODULE, {update_node, Node, Dsts}).

-spec(delete_node(Node :: node()) -> ok).
delete_node(Node) ->
  gen_statem:cast(?MODULE, {delete_node, Node}).

%% @doc
%% Checks the reachability from this node to node Node
%% @end
-spec(reachable(Node :: node()) -> true | false).
reachable(Node) when Node == node() -> true;
reachable(Node) ->
  case get_tree(node()) of
    {tree, Tree} ->
      distance(Node, Tree) =/= infinity;
    _ ->
      false
  end.


-spec(path_to(Node :: node()) -> [node()] | false).
path_to(Node) ->
  case get_tree(node()) of
    {tree, Tree} ->
      path_to(Node, Tree);
    _ ->
      false
  end.


-spec(path_to(Node :: node(), Tree :: tree()) -> false | [node()]).
path_to(Node, Tree) ->
  case distance(Node, Tree) of
    infinity ->
      false;
    _ ->
      path_to(Node, Tree, [Node])
  end.

-spec(path_to(Node :: node(), Tree :: tree(), Path :: [node()]) -> [node()]).
path_to(Node, Tree, Acc) ->
  Entry = maps:get(Node, Tree),
  case Entry of
    #tree_entry{distance = 0} ->
      Acc;
    #tree_entry{parent = Parent} ->
      path_to(Parent, Tree, [Parent|Acc])
  end.

-spec(get_tree(Node :: node()) -> {tree, tree()} | false).
get_tree(Node) ->
  get_tree(Node, 5000).

-spec(get_tree(Node :: node(), Timeout :: non_neg_integer() | infinity) -> {tree, tree()} | false).
get_tree(Node, Timeout) ->
  gen_statem:call(?MODULE, {get_tree, Node}, Timeout).

-spec(distance(Node :: node(), Tree :: tree()) -> non_neg_integer() | infinity).
distance(Node, Tree) ->
  case Tree of
    #{Node := Entry} ->
      Entry#tree_entry.distance;
    _ ->
      infinity
  end.

-spec(reachable_nodes(Tree :: tree()) -> [node()]).
reachable_nodes(Tree) ->
  TreeEntries =
    maps:filter(
      fun(_Key, _TreeEntry = #tree_entry{distance = Distance}) ->
        Distance =/= infinity
      end,
      Tree),
  maps:keys(TreeEntries).

-spec(unreachable_nodes(Tree :: tree()) -> [node()]).
unreachable_nodes(Tree) ->
  TreeEntries =
    maps:filter(
      fun(_Key, _TreeEntry = #tree_entry{distance = Distance}) ->
        Distance == infinity
      end,
      Tree),
  maps:keys(TreeEntries).

-spec(reverse_children(Parent :: node(), Tree :: tree()) -> [node()]).
reverse_children(Parent, Tree) ->
  TreeEntries =
    maps:filter(
      fun(_Node, _TreeEntry = #tree_entry{parent = P, distance = Distance}) ->
        P == Parent andalso Distance =/= 0
      end,
      Tree),
  maps:keys(TreeEntries).

-spec(children(Parent :: node(), Tree :: tree()) -> [node()]).
children(Parent, Tree) ->
  #{Parent := #tree_entry{children = Children}} = Tree,
  Children.

%% @doc
%% Ensures there is a path between the root and the node
%% @end
-spec(prune_tree(Node :: node(), Tree :: tree()) -> tree()).
prune_tree(Node, Tree) ->
  prune_tree(Node, Tree, #{}).
-spec(prune_tree(Node :: node(), Tree :: tree(), PrunedTree :: tree()) -> tree()).
prune_tree(Node, Tree, PrunedTree) ->
  case maps:get(Node, Tree, unknown) of
    unknown ->
      %% We did the best we could
      PrunedTree;
    TreeEntry = #tree_entry{distance = 0} ->
      PrunedTree#{Node => TreeEntry};
    TreeEntry = #tree_entry{parent = Parent} ->
      PrunedTree1 = PrunedTree#{Node => TreeEntry},
      prune_tree(Parent, Tree, PrunedTree1)
  end.

flush_events_helper() ->
  gen_statem:cast(?MODULE, flush_events_helper).

-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_statem:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

init([]) ->
  Interval = trunc(200 + rand:uniform(50)),
  timer:send_interval(Interval, decrement_busy),
  vertices = ets:new(vertices, [set, named_table, {keypos, #vertex.node}]),
  {ok, idle, #state{}}.

callback_mode() ->
  handle_event_function.

%% Get tree logic
handle_event({call, From}, {get_tree, Node}, cached, StateData0) when Node == node() ->
  {StateData1, Reply} = handle_get_tree(Node, StateData0),
  {keep_state, StateData1, {reply, From, Reply}};
handle_event({call, From}, {get_tree, Node}, _StateName, StateData0 = #state{events = EC}) when Node == node() ->
  {StateData1, Reply} = handle_get_tree(Node, StateData0),
  {next_state, cached, StateData1#state{events = EC + 1}, {reply, From, Reply}};
handle_event({call, From}, {get_tree, Node}, _StateName, StateData0 = #state{events = EC}) ->
  {StateData1, Reply} = handle_get_tree(Node, StateData0),
  {keep_state, StateData1#state{events = EC + 1}, {reply, From, Reply}};

%% Rewrite all other calls into synchronous casts (for testing)
handle_event({call, From}, EventContent, StateName, StateData0) ->
  Ret = handle_event(cast, EventContent, StateName, StateData0),
  gen_statem:reply(From, ok),
  Ret;

%% Rewrite flush_events message into an advertise message
handle_event(cast, flush_events_helper, _StateName, _StateData0) ->
  {keep_state_and_data, [{next_event, internal, maybe_advertise_state}]};

%% Advertisements for cached state are free
handle_event(internal, maybe_advertise_state, cached, StateData0) ->
  {StateData1, {tree, Tree}} = handle_get_tree(node(), StateData0),
  lashup_gm_route_events:ingest(Tree),
  {keep_state, StateData1};
handle_event(internal, maybe_advertise_state, _StateName, StateData = #state{events = EC}) when EC > 5 ->
  %% Ignore that the tree is dirty
  {next_state, busy, StateData};
handle_event(internal, maybe_advertise_state, _StateName, StateData0 = #state{events = EC}) ->
  {StateData1, {tree, Tree}} = handle_get_tree(node(), StateData0),
  lashup_gm_route_events:ingest(Tree),
  {next_state, cached, StateData1#state{events = EC + 1}};

handle_event(info, decrement_busy, busy, StateData0 = #state{events = EC}) ->
  {keep_state, StateData0#state{events = max(0, EC - 1)}, [{next_event, internal, maybe_advertise_state}]};
handle_event(info, decrement_busy, _, StateData0 = #state{events = EC}) ->
  {keep_state, StateData0#state{events = max(0, EC - 1)}};

handle_event(cast, {update_node, Node, Dsts}, _StateName, StateData0) ->
  StateData1 = handle_update_node(Node, Dsts, StateData0),
  {next_state, dirty_tree, StateData1, [{next_event, internal, maybe_advertise_state}]};
handle_event(cast, {delete_node, Node}, _StateName, StateData0) ->
  StateData1 = handle_delete_node(Node, StateData0),
  {next_state, dirty_tree, StateData1, [{next_event, internal, maybe_advertise_state}]}.

terminate(Reason, State, Data = #state{}) ->
  lager:warning("Terminating in State: ~p, due to reason: ~p, with data: ~p", [State, Reason, Data]),
  ok.

code_change(_OldVsn, OldState, OldData, _Extra) ->
  {ok, OldState, OldData}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% TODO:
%% -Handle short-circuiting updating the tree if we're seeing too many events per second
%% -Add metrics around tree updates / sec

-spec(handle_get_tree(Root :: node(), State :: state()) -> {state(), {tree, tree()}}).
handle_get_tree(Root, State0 = #state{cache = Cache0}) ->
  case Cache0 of
    #{Root := Tree} ->
      {State0, {tree, Tree}};
    _ ->
      Tree = build_tree(Root),
      State1 = State0#state{cache = Cache0#{Root => Tree}},
      {State1, {tree, Tree}}
  end.

-spec(handle_update_node(Node :: node(), Edges :: [node()], State :: state()) -> state()).
handle_update_node(Node, Dsts, State0) ->
  Dsts1 = lists:usort(Dsts),
  InitialNeighbors = neighbors(Node),
  persist_node(Node),
  % Ensure that the dsts exist
  [persist_node(Dst) || Dst <- Dsts1],
  update_edges(Node, Dsts1),
  %% We only bust the caches is the adjacency list has changed.
  %% Once we have properties on adjacencies and vertices,
  %% We have to augment this
  case Dsts1 of
    InitialNeighbors ->
      State0;
    _ ->
      bust_cache(State0)
  end.

-spec(handle_delete_node(Node ::node(), State :: state()) -> state()).
handle_delete_node(Node, State0) ->
  ets:delete(vertices, Node),
  State1 = handle_delete_node(Node, ets:first(vertices), State0),
  bust_cache(State1).

-spec(handle_delete_node(DstNode :: node(), CurNode :: node() | '$end_of_table', State :: state()) -> state()).
handle_delete_node(_DstNode, '$end_of_table', State) -> State;
handle_delete_node(DstNode, CurNode, State) ->
  Dsts0 = ets:lookup_element(vertices, CurNode, #vertex.dsts),
  case ordsets:del_element(DstNode, Dsts0) of
    Dsts0 ->
      State;
    Dsts1 ->
      ets:update_element(vertices, CurNode, {#vertex.dsts, Dsts1})
  end,
  handle_delete_node(DstNode, ets:next(vertices, CurNode), State).

bust_cache(State0 = #state{}) ->
  State0#state{cache = #{}}.

update_edges(Node, Dsts) ->
  true = ets:update_element(vertices, Node, {#vertex.dsts, Dsts}).

neighbors(Node) ->
  %% Ets lookup should _always_ return in order.
  %% This means we do not need to ordset, since ets already does:
  %% (1) Dedupe (which shouldn't happen
  %% (2) Sort the list, because it ensure we always take the same path ("smallest") when building the BFS
  %%      since we add the nodes in order
  case ets:lookup(vertices, Node) of
    [] -> [];
    [Vertex] ->
      Vertex#vertex.dsts
  end.

-spec(persist_node(Node :: node()) -> boolean()).
persist_node(Node) ->
  Vertex = #vertex{node = Node},
  ets:insert_new(vertices, Vertex).

%% @doc
%% Build the tree representation for Node = root
%% @end

%% We could put the tree in ets, but right now it's on the process heap
%% We do store it in the tree_cache table
%% The reason that it's not stored in an ets table is that it's a pain
%% to incrementally (safely) update the tree

%% We can't edit the tree while other people are observing it
%% And this process can stall out for a little bit

%% Therefore, we have this workaround of stashing the tree in a serialized object
%% Also, we assume the routing table never grows to more than ~10k nodes

-spec(build_tree(node()) -> tree()).
build_tree(Node) ->
  Tree = ets:foldl(fun initialize_tree/2, #{}, vertices),
  %% Special case - it's its own parent
  Tree1 = update_node(Node, Node, 0, Tree),
  Queue = queue:new(),
  Queue1 = queue:in(Node, Queue),
  build_tree(Queue1, Tree1).

initialize_tree(_Node = #vertex{node = Key}, Tree) ->
  Tree#{Key => #tree_entry{}}.

-spec(update_node(Node :: node(), Parent :: node(), Distance :: distance(), Tree :: tree()) -> tree()).
%% The exceptional case for the root node
update_node(Node, Parent, Distance, Tree) when Node == Parent ->
  Entry0 = maps:get(Node, Tree, #tree_entry{}),
  Entry1 = Entry0#tree_entry{distance = Distance, parent = Parent},
  Tree#{Node => Entry1};
update_node(Node, Parent, Distance, Tree) ->
  Entry0 = maps:get(Node, Tree),
  Entry1 = Entry0#tree_entry{distance = Distance, parent = Parent},
  ParentEntry0 = #tree_entry{children = Children0} = maps:get(Parent, Tree, #tree_entry{}),
  Children1 = ordsets:add_element(Node, Children0),
  ParentEntry1 = ParentEntry0#tree_entry{children = Children1},
  Tree#{Node => Entry1, Parent => ParentEntry1}.
  %Tree#{Node => NewEntry}.


build_tree(Queue, Tree) ->
  case queue:out(Queue) of
    {{value, Current}, Queue2} ->
      Neighbors = neighbors(Current),
      FoldFun = fun(Neighbor, Acc) -> update_adjacency(Current, Neighbor, Acc) end,
      {Queue3, Tree1} = lists:foldl(FoldFun, {Queue2, Tree}, Neighbors),
      build_tree(Queue3, Tree1);
    {empty, Queue} ->
      Tree
  end.

%% BFS - https://en.wikipedia.org/wiki/Breadth-first_search
update_adjacency(Current, Neighbor, {Queue, Tree}) ->
  case distance(Neighbor, Tree) of
    infinity ->
      NewDistance = distance(Current, Tree) + 1,
      Tree1 = update_node(Neighbor, Current, NewDistance, Tree),
      Queue1 = queue:in(Neighbor, Queue),
      {Queue1, Tree1};
    _ ->
      {Queue, Tree}
  end.

-ifdef(TEST).

proper_test_() ->
  {timeout,
    3600,
    [fun proper/0]
  }.

proper() ->
  [] = proper:module(?MODULE, [{numtests, 10000}]).

initial_state() ->
  Initial = #{},
  Digraph = digraph:new(),
  update_state(Digraph, Initial).

state_to_digraph(_State = #{family := Family}) ->
  sofs:family_to_digraph(Family).

update_state(Digraph, State) ->
  Family = sofs:digraph_to_family(Digraph),
  digraph:delete(Digraph),
  State#{family => Family}.

get_path(_State = #{family := Family}, A, B) ->
  Digraph = sofs:family_to_digraph(Family),
  Result = digraph:get_path(Digraph, A, B),
  digraph:delete(Digraph),
  Result.

get_short_path(_State = #{family := Family}, A, B) ->
  Digraph = sofs:family_to_digraph(Family),
  Result = digraph:get_short_path(Digraph, A, B),
  digraph:delete(Digraph),
  Result.


-define(NODES, [
  node(),
  node1@localhost, node2@localhost, node3@localhost,
  node4@localhost, node5@localhost, node6@localhost,
  node7@localhost, node8@localhost, node9@localhost,
  node10@localhost, node11@localhost, node12@localhost,
  node13@localhost, node14@localhost, node15@localhost,
  node16@localhost, node17@localhost, node18@localhost,
  node19@localhost, node20@localhost, node21@localhost,
  node22@localhost, node23@localhost, node24@localhost,
  node25@localhost
]).

precondition(_State, _Call) -> true.

postcondition(_State, {call, ?MODULE, reachable, [Node]}, Result) when Node == node() ->
  true == Result;
postcondition(State, {call, ?MODULE, reachable, [Node]}, Result) ->
  GetPath = get_path(State, node(), Node),
  is_list(GetPath) ==  Result;

%% This is a divergence from the digraph module
%% If the node is in our routing table
%% We will say the route back to the node is itself.
postcondition(_State, {call, ?MODULE, verify_routes, [FromNode, ToNode]}, Result) when FromNode == ToNode ->
  %% A node always has a route to itself.
  Result == [FromNode];
postcondition(State, {call, ?MODULE, verify_routes, [FromNode, ToNode]}, Result) ->
  DigraphPath = get_short_path(State, FromNode, ToNode),
  case {Result, DigraphPath}  of
    {false, false} ->
      true;
    {false, P} when is_list(P) ->
      false;
    {P, false} when is_list(P) ->
      false;
    {Path1, Path2} when Path1 == Path2 ->
      true;
    {Path1, Path2} when length(Path1) =/= length(Path2) ->
      false;
    %% This is to take care of the case when there are multiple shortest paths
    {Path1, _Path2} ->
      Digraph = state_to_digraph(State),
      Subgraph = digraph_utils:subgraph(Digraph, Path1),
      digraph:delete(Digraph),
      SubgraphPath = digraph:get_short_path(Subgraph, FromNode, ToNode),
      digraph:delete(Subgraph),
      Path1 == SubgraphPath
  end;
postcondition(_State, _Call, _Result) -> true.

next_state(State, _V,
    {call, gen_statem, call, [lashup_gm_route, {update_node, Node, NewNodes}]}) ->
  Digraph = state_to_digraph(State),
  digraph:add_vertex(Digraph, Node),
  [digraph:add_vertex(Digraph, NewNode) || NewNode <- NewNodes],
  OldEdges = digraph:out_edges(Digraph, Node),
  [digraph:del_edge(Digraph, OldEdge) || OldEdge <- OldEdges],
  [digraph:add_edge(Digraph, Node, NewNode) || NewNode <- NewNodes],
  update_state(Digraph, State);

next_state(State, _V,
  {call, gen_statem, call, [lashup_gm_route, {delete_node, Node}]}) ->
  Digraph = state_to_digraph(State),
  digraph:del_vertex(Digraph, Node),
  update_state(Digraph, State);

next_state(State, _V, _Call) ->
  State.

node_gen() ->
  oneof(?NODES).

node_gen_list(Except) ->
  list(elements(?NODES -- [Except])).

update_node_gen() ->
  ?LET(Node, oneof(?NODES), {update_node, Node, node_gen_list(Node)}).

verify_routes(FromNode, ToNode) ->
  case get_tree(FromNode) of
    false ->
      false;
    {tree, Tree} ->
      path_to(ToNode, Tree)
  end.

command(_S) ->
  oneof([
      {call, gen_statem, call, [?MODULE, update_node_gen()]},
      {call, gen_statem, call, [?MODULE, {delete_node, node_gen()}]},
      {call, ?MODULE, reachable, [node_gen()]},
      {call, ?MODULE, verify_routes, [node_gen(), node_gen()]}
    ]).


prop_server_works_fine() ->
  ?FORALL(Cmds, commands(?MODULE),
    ?TRAPEXIT(
      begin
        ?MODULE:start_link(),
        {History, State, Result} = run_commands(?MODULE, Cmds),
        ?MODULE:stop(),
        ?WHENFAIL(io:format("History: ~p\nState: ~p\nResult: ~p\n",
          [History, State, Result]),
          Result =:= ok)
      end)).

stop() ->
  gen_statem:stop(?MODULE).

-endif.
