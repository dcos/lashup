%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. Jan 2016 3:53 PM
%%%-------------------------------------------------------------------
-module(lashup_hyparview_SUITE).
-author("sdhillon").
-compile({parse_transform, lager_transform}).

-include_lib("common_test/include/ct.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([hyparview_test/1, failure_test/1]).

-define(SLAVES, [list_to_atom(lists:flatten(io_lib:format("slave~p", [X]))) || X <- lists:seq(1, 50)]).
-define(MASTERS, [master1, master2]).

all() ->
  [hyparview_test, failure_test].

init_per_suite(Config) ->
  {Masters, Slaves} = start_nodes(),
  [{masters, Masters}, {slaves, Slaves}|Config].

end_per_suite(Config) ->
  stop_nodes(?config(slaves, Config)),
  stop_nodes(?config(masters, Config)).


start_nodes() ->
  Results = rpc:pmap({ct_slave, start}, [[{monitor_master, true}, {erl_flags, "-connect_all false"}]], ?MASTERS ++ ?SLAVES),
  Nodes = [NodeName || {ok, NodeName} <- Results],
  {Masters, Slaves} = lists:split(length(?MASTERS), Nodes),
  CodePath = code:get_path(),
  Handlers = [
    {lager_console_backend, debug},
    {lager_file_backend, [{file, "error.log"}, {level, error}]},
    {lager_file_backend, [{file, "console.log"}, {level, debug},
        {formatter, lager_default_formatter}, {formatter_config, [node, ": ", time," [",severity,"] ", pid, " (", module, ":", function, ":", line, ")", " ", message, "\n"]}
      ]},
    {lager_common_test_backend, debug }
  ],
  rpc:multicall(Nodes, code, set_path, [CodePath]),
  rpc:multicall(Nodes, application, set_env, [lager, handlers, Handlers, [{persistent, true}]]),
  rpc:multicall(Nodes, application, ensure_all_started, [lager]),
  {_, []} = rpc:multicall(Masters, application, set_env, [lashup, contact_nodes, Masters]),
  {_, []} = rpc:multicall(Slaves, application, set_env, [lashup, contact_nodes, Masters]),

  {Masters, Slaves}.

stop_nodes(Nodes) ->
  lists:foreach(fun ct_slave:stop/1, Nodes).

hyparview_test(Config) ->
  application:ensure_all_started(lager),
  _Status = rpc:multicall(?config(masters, Config), application, ensure_all_started, [lashup]),
  rpc:multicall(?config(slaves, Config), application, ensure_all_started, [lashup]),
  %PWDs = rpc:multicall(?config(masters, Config) ++ ?config(slaves, Config), application, which_applications, []),
  %timer:apply_interval(1000, erlang, apply, [DumpFun, []]),
  LeftOverTime = wait_for_convergence(600000, 5000, ?config(slaves, Config) ++ ?config(masters, Config)),
  Paths = check_graph(?config(slaves, Config) ++ ?config(masters, Config)),
  PathLens = [length(Path)|| {{_V1, _V2}, Path} <- Paths, Path =/= false],
  MaxLen = lists:max(PathLens),
  MinLen = lists:min(PathLens),
  Mean = lists:sum(PathLens) / length(PathLens),
  SortedPathLens = lists:sort(PathLens),
  Median = lists:nth(round(length(PathLens) / 2), SortedPathLens),
  ct:pal("Max Path length: ~p~nMin Path length: ~p~nMean Path length: ~p~nMedian Path Length: ~p~n", [MaxLen, MinLen, Mean, Median]),
  ct:pal("Converged in ~p milliseconds", [600000-LeftOverTime]),
  ok.

failure_test(Config) ->
  ct:pal("Testing failure conditions"),
  Nodes = ?config(slaves, Config) ++ ?config(masters, Config),
  N = round(length(Nodes) / 2),
  {Nodes1, Nodes2} = lists:split(N, Nodes),
  ct:pal("Splitting networks"),
  rpc:multicall(Nodes1, net_kernel, allow, [[node()|Nodes1]]),
  rpc:multicall(Nodes2, net_kernel, allow, [[node()|Nodes2]]),
  lists:foreach(fun(Node) -> rpc:multicall(Nodes1, erlang, disconnect_node, [Node]) end, Nodes2),
  lists:foreach(fun(Node) -> rpc:multicall(Nodes2, erlang, disconnect_node, [Node]) end, Nodes1),

  ct:pal("Allowing either side to converge independently"),
  wait_for_convergence(600000, 5000, Nodes1),
  wait_for_convergence(600000, 5000, Nodes2),

  ct:pal("Healing networks"),
  rpc:multicall(Nodes, net_kernel, allow, [node()|Nodes]),
  LeftOverTime = wait_for_convergence(600000, 5000, ?config(slaves, Config) ++ ?config(masters, Config)),
  Paths = check_graph(?config(slaves, Config) ++ ?config(masters, Config)),
  PathLens = [length(Path)|| {{_V1, _V2}, Path} <- Paths, Path =/= false],
  MaxLen = lists:max(PathLens),
  MinLen = lists:min(PathLens),
  Mean = lists:sum(PathLens) / length(PathLens),
  SortedPathLens = lists:sort(PathLens),
  Median = lists:nth(round(length(PathLens) / 2), SortedPathLens),
  ct:pal("Max Path length: ~p~nMin Path length: ~p~nMean Path length: ~p~nMedian Path Length: ~p~n", [MaxLen, MinLen, Mean, Median]),
  ct:pal("Converged in ~p milliseconds", [600000-LeftOverTime]),
  ok.




wait_for_convergence(TotalTime, Interval, Nodes) when TotalTime > 0->
  timer:sleep(Interval),
  case check_converged(Nodes) of
    true ->
      TotalTime;
    false ->
      ct:pal("Unconverged at: ~p remaining~n", [TotalTime]),
      check_graph(Nodes),
      wait_for_convergence(TotalTime - Interval, Interval, Nodes)
  end;

wait_for_convergence(_TotalTime, _Interval, Nodes) ->
  {Replies, _} = gen_server:multi_call(Nodes, lashup_hyparview_membership, get_active_view),
  ActiveViews = lists:flatten([ActiveView || {_Node, ActiveView} <- Replies]),
  InitDict = lists:foldl(fun(Node, Acc) -> orddict:update_counter(Node, 0, Acc) end, [], Nodes),
  DictCounted = lists:foldl(fun(Node, Acc) -> orddict:update_counter(Node, 1, Acc) end, InitDict, ActiveViews),
  UnconvergedEgress = lists:flatten([ActiveView || {_Node, ActiveView} <- Replies, length(ActiveView) < 3]),
  UnconvergedIngress = orddict:filter(fun(_Key, Value) -> Value == 0 end, DictCounted),
  ct:pal("Unconverged Egress: ~p", [UnconvergedEgress]),
  ct:pal("Unconverged Ingress: ~p", [UnconvergedIngress]),
  ct:fail(never_converged).

check_converged(Nodes) ->
  %% Make sure all the nodes know about each other
  %% Make sure all the active views are full
  {Replies, _} = gen_server:multi_call(Nodes, lashup_hyparview_membership, get_active_view),
  ActiveViews = lists:flatten([ActiveView || {_Node, ActiveView} <- Replies]),
  InitDict = lists:foldl(fun(Node, Acc) -> orddict:update_counter(Node, 0, Acc) end, [], Nodes),
  DictCounted = lists:foldl(fun(Node, Acc) -> orddict:update_counter(Node, 1, Acc) end, InitDict, ActiveViews),
  EnsureAllIngress = [] == orddict:filter(fun(_Key, Value) -> Value == 0 end, DictCounted),
  %% Ensure we have at least 2 egress paths in every node's active view

  EnsureEgressOf2OrMore = [] == lists:flatten([ActiveView || {_Node, ActiveView} <- Replies, length(ActiveView) < 3]),
  EnsureAllIngress andalso EnsureEgressOf2OrMore.


check_graph(Nodes) ->
  Digraph = digraph:new(),
  lists:foreach(fun(Node) -> digraph:add_vertex(Digraph, Node) end, Nodes),
  AddEdges =
    fun(Node) ->
      ActiveView = gen_server:call({lashup_hyparview_membership, Node}, get_active_view),
      lists:foreach(fun(V2) -> digraph:add_edge(Digraph, Node, V2) end, ActiveView)
    end,
  lists:foreach(AddEdges, Nodes),
  Paths = [check_path(Digraph, V1, V2) || V1 <- Nodes, V2 <- Nodes, V1 =/= V2],
  BadPaths = [{"No path between ~p and ~p~n", [V1, V2]} || {{V1, V2}, false} <- Paths],
  {Strings, Variables} = lists:unzip(BadPaths),
  FlatStrings = lists:flatten(Strings),
  FlatVariables = lists:flatten(Variables),
  ct:pal(FlatStrings, FlatVariables),
  digraph:delete(Digraph),
  Paths.

check_path(G, V1, V2) when V1 =/= V2->
  {{V1, V2}, digraph:get_short_path(G, V1, V2)}.