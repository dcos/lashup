%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%% An LSA routing database (RIB) routing information base
%%% It has a cache that makes it suitable for a FIB
%%%
%%% @end
%%% Created : 05. Feb 2016 6:14 PM
%%%-------------------------------------------------------------------
%%% TODO:
%%% -Determine whether it makes more sense to stash the graph in a sofs
%%% -Determine whether it makes sense to use sofs rather than maps to store the BFS trees
-module(lashup_gm_route).
-author("sdhillon").

-behaviour(gen_server).

%% API
-export([
  start_link/0,
  update_node/2,
  delete_node/1,
  reachable/1,
  get_tree/1,
  distance/2,
  reachable_nodes/1,
  unreachable_nodes/1,
  path_to/1,
  path_to/2,
  children/2,
  prune_tree/2
]).


-ifdef(TEST).
-behaviour(proper_statem).

-export([proper/0]).

-export([initial_state/0,
  stop/0,
  command/1,
  precondition/2,
  postcondition/3,
  next_state/3
]).
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-endif.

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {cache_version = 0 :: non_neg_integer()}).
-type state() :: state().

-type distance() :: non_neg_integer() | infinity.
-type tree() :: map().
-export_type([tree/0]).

%% Egress paths = active view
-record(vertex, {
  node = erlang:error() :: node()
}).

-record(edge, {
  src = erlang:error() :: node(),
  dst = erlang:error() :: node()
}).
-record(tree_entry, {
  parent = undefined :: node() | undefined,
  distance = infinity :: non_neg_integer() | infinity
}).

-record(tree_cache, {
  root = erlang:error() :: node(),
  tree = erlang:error() :: tree(),
  cache_ver = erlang:error() :: non_neg_integer()
}).


-include_lib("stdlib/include/ms_transform.hrl").

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
  DstsSet = ordsets:from_list(Dsts),
  gen_server:cast(?SERVER, {update_node, Node, DstsSet}).

-spec(delete_node(Node :: node()) -> ok).
delete_node(Node) ->
  gen_server:cast(?SERVER, {delete_node, Node}).

%% @doc
%% Checks the reachability from this node to node Node
%% @end
-spec(reachable(Node :: node()) -> true | false).
reachable(Node) when Node == node() -> true;
reachable(Node) ->
  case catch get_tree(node()) of
    {tree, Tree} ->
      distance(Node, Tree) =/= infinity;
    _ ->
      false
  end.


-spec(path_to(Node :: node()) -> [node()] | false).
path_to(Node) ->
  case catch get_tree(node()) of
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
  case fetch_tree_from_cache(Node) of
    {tree, Tree} ->
      {tree, Tree};
    false ->
      gen_server:call(?SERVER, {get_tree, Node})
  end.


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

-spec(children(Parent :: node(), Tree :: tree()) -> [node()]).
children(Parent, Tree) ->
  TreeEntries =
    maps:filter(
      fun(_Node, _TreeEntry = #tree_entry{parent = P, distance = Distance}) ->
        P == Parent andalso Distance =/= 0
      end,
      Tree),
  maps:keys(TreeEntries).

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
  tree_cache = ets:new(tree_cache, [set, named_table, {read_concurrency, true}, {keypos, #tree_cache.root}]),
  vertices = ets:new(vertices, [set, named_table, {keypos, #vertex.node}]),
  edges = ets:new(edges, [bag, named_table, {keypos, #edge.src}]),
  {ok, #state{}}.

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
handle_call({update_node, Node, Dsts}, _From, State) ->
  State1 = handle_update_node(Node, Dsts, State),
  {reply, ok, State1};
handle_call({get_tree, Root}, _From, State) ->
  Reply = handle_get_tree(Root, State),
  {reply, Reply, State};
handle_call({delete_node, Node}, _From, State) ->
  State1 = handle_delete_node(Node, State),
  {reply, ok, State1};
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
handle_cast({update_node, Node, Dsts}, State) ->
  State1 = handle_update_node(Node, Dsts, State),
  {noreply, State1};
handle_cast({delete_node, Node}, State) ->
  State1 = handle_delete_node(Node, State),
  {noreply, State1};
handle_cast(Request, State) ->
  lager:debug("Unknown request: ~p", [Request]),
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
handle_info(_Info, State) ->
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

%% TODO:
%% -Handle short-circuiting updating the tree if we're seeing too many events per second
%% -Add metrics around tree updates / sec

handle_get_tree(Root, State) ->
  case fetch_tree_from_cache(Root, State) of
    {tree, Tree} ->
      {tree, Tree};
    false ->
      maybe_build_and_cache_tree(Root, State)
  end.


-spec(handle_update_node(Node :: node(), Edges :: [node()], State :: state()) -> state()).
handle_update_node(Node, Dsts, State) ->
  Dsts1 = lists:usort(Dsts),
  InitialNeighbors = neighbors(Node),
  persist_node(Node),
  % Ensure that the dsts exist
  [persist_node(Dst) || Dst <- Dsts1],
  update_edges(Node, Dsts1),
  %% We only bust the caches is the adjacency list has changed.
  %% Once we have properties on adjacencies and vertices,
  %% We have to augment this
  case Dsts of
    InitialNeighbors ->
      State;
    _ ->
      update_local_tree(State)
  end.

-spec(handle_delete_node(Node ::node(), State :: state()) -> state()).
handle_delete_node(Node, State) ->
  ets:delete(vertices, Node),
  MatchSpec1 = ets:fun2ms(fun(#edge{dst = Dst}) when Dst == Node -> true end),
  ets:select_delete(edges, MatchSpec1),
  MatchSpec2 = ets:fun2ms(fun(#edge{src = Src}) when Src == Node -> true end),
  ets:select_delete(edges, MatchSpec2),
  update_local_tree(State).

update_local_tree(State) ->
  Root = node(),
  NewCacheVersion = State#state.cache_version + 1,
  State1 = State#state{cache_version = NewCacheVersion},
  maybe_build_and_cache_tree(Root, State1),
  bust_cache(State1),
  State1.

bust_cache(_State = #state{cache_version = CacheVersion}) ->
  MatchSpec = ets:fun2ms(fun(#tree_cache{cache_ver = CV}) when CV =/= CacheVersion -> true end),
  ets:select_delete(tree_cache, MatchSpec).

update_edges(Node, Dsts) ->
  add_new_edges(Node, Dsts),
  trim_edges(Node, Dsts).

-spec(add_new_edges(Node :: node(), Dsts :: [node()]) -> ok).
add_new_edges(Node, Dsts) ->
  NewEdgeRecords = [#edge{src = Node, dst = Dst} || Dst <- Dsts],
  [true = ets:insert(edges, NewEdgeRecord) || NewEdgeRecord <- NewEdgeRecords],
  ok.

-spec(trim_edges(Node :: node(), Dsts :: [node()]) -> non_neg_integer()).
trim_edges(Node, Dsts) ->
  Old = neighbors(Node),
  NeighborsToDelete = ordsets:subtract(Old, Dsts),
  EdgesToDelete = [#edge{src = Node, dst = Neighbor} || Neighbor <- NeighborsToDelete],
  Deleted = [ets:delete_object(edges, Edge) || Edge <- EdgesToDelete],
  length(Deleted).

neighbors(Node) ->
  DstsEdges = ets:lookup(edges, Node),
  Dsts = [Edge#edge.dst || Edge <- DstsEdges],
  %% We ordset it to:
  %% (1) Dedupe (which shouldn't happen
  %% (2) Sort the list, because it ensure we always take the same path ("smallest") when building the BFS
  %%      since we add the nodes in order
  ordsets:from_list(Dsts).

-spec(persist_node(Node :: node()) -> boolean()).
persist_node(Node) ->
  Vertex = #vertex{node = Node},
  ets:insert_new(vertices, Vertex).

-spec(fetch_tree_from_cache(Node :: node()) -> {tree, tree()} | false).
fetch_tree_from_cache(Node) when Node == node()->
  case ets:lookup(tree_cache, Node) of
    [TreeCache] ->
      {tree, TreeCache#tree_cache.tree};
    [] ->
      false
  end;
fetch_tree_from_cache(Node) ->
  case ets:lookup(tree_cache, Node) of
    [TreeCache] ->
      {tree, TreeCache#tree_cache.tree};
    [] ->
      false
  end.


%% @doc
%% Checks to ensure that the tree is cache coherent
%% @end
fetch_tree_from_cache(Node, _State = #state{cache_version = CacheVersion}) ->
  case ets:lookup(tree_cache, Node) of
    [TreeCache = #tree_cache{cache_ver = CacheVersion}] ->
      {tree, TreeCache#tree_cache.tree};
    [_TreeCache = #tree_cache{}] ->
      false;
    [] ->
      false
  end.

maybe_build_and_cache_tree(Node, _State = #state{cache_version = CacheVersion}) ->
  case ets:lookup(vertices, Node) of
    [] ->
      false;
    _ ->
      Tree = build_tree(Node),
      ets:insert(tree_cache, #tree_cache{cache_ver = CacheVersion, root = Node, tree = Tree}),
      {tree, Tree}
  end.

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
update_node(Node, Parent, Distance, Tree) ->
  Entry = maps:get(Node, Tree),
  NewEntry = Entry#tree_entry{distance = Distance, parent = Parent},
  Tree#{Node => NewEntry}.


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
-compile(export_all).


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


  -define(NODES, [node(), node1@localhost, node2@localhost, node3@localhost,
  node4@localhost, node5@localhost, node6@localhost,
  node7@localhost, node8@localhost, node9@localhost,
  node10@localhost, node11@localhost, node12@localhost,
  node13@localhost, node14@localhost, node15@localhost,
  node16@localhost, node17@localhost, node18@localhost,
  node19@localhost, node20@localhost, node21@localhost,
  node22@localhost, node23@localhost, node24@localhost,
  node25@localhost]).

precondition(_State, _Call) -> true.


postcondition(_State, {call, ?MODULE, reachable, [Node]}, Result) when Node == node() ->
  true == Result;
postcondition(State, {call, ?MODULE, reachable, [Node]}, Result) ->
  GetPath = get_path(State, node(), Node),
  is_list(GetPath) ==  Result;

%% This is a divergence from the digraph module
%% If the node is in our routing table
%% We will say the route back to the node is itself.
postcondition(State, {call, ?MODULE, verify_routes, [FromNode, ToNode]}, Result) when FromNode == ToNode ->
  Digraph = state_to_digraph(State),
  PostCondition =
  case digraph:vertex(Digraph, FromNode) of
    false ->
      Result == false;
    _ ->
      Result == [FromNode]
  end,
  digraph:delete(Digraph),
  PostCondition;
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
    {call, gen_server, call, [lashup_gm_route, {update_node, Node, NewNodes}]}) ->
  Digraph = state_to_digraph(State),
  digraph:add_vertex(Digraph, Node),
  [digraph:add_vertex(Digraph, NewNode) || NewNode <- NewNodes],
  OldEdges = digraph:out_edges(Digraph, Node),
  [digraph:del_edge(Digraph, OldEdge) || OldEdge <- OldEdges],
  [digraph:add_edge(Digraph, Node, NewNode) || NewNode <- NewNodes],
  update_state(Digraph, State);

next_state(State, _V,
  {call, gen_server, call, [lashup_gm_route, {delete_node, Node}]}) ->
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
      {call, gen_server, call, [?MODULE, update_node_gen()]},
      {call, gen_server, call, [?MODULE, {delete_node, node_gen()}]},
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
  gen_server:stop(?SERVER).

-endif.

