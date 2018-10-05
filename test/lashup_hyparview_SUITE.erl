-module(lashup_hyparview_SUITE).
-author("sdhillon").

-include_lib("common_test/include/ct.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2, init_per_suite/1, end_per_suite/1]).
-export([hyparview_test/1, failure_test0/1, failure_test60/1,
  failure_test120/1, failure_test300/1, hyparview_random_kill_test/1, ping_test/1, mc_test/1,
  kv_test/1]).

-define(MAX_MC_REPLICATION, 3).


init_per_suite(Config) ->
  %% this might help, might not...
  os:cmd(os:find_executable("epmd") ++ " -daemon"),
  {ok, Hostname} = inet:gethostname(),
  case net_kernel:start([list_to_atom("runner@" ++ Hostname), shortnames]) of
    {ok, _} -> ok;
    {error, {already_started, _}} -> ok
  end,
  Config.

end_per_suite(Config) ->
  net_kernel:stop(),
  Config.

all() ->
  BaseTests = [hyparview_test, hyparview_random_kill_test, ping_test, mc_test, kv_test],
  case ci() of
    true ->
      BaseTests ++ [failure_test300];
    false ->
      BaseTests ++ [failure_test0, failure_test60]
  end.

init_per_testcase(TestCaseName, Config) ->
  ct:pal("Starting Testcase: ~p", [TestCaseName]),
  {Masters, Slaves} = start_nodes(),
  {Pids, _} = rpc:multicall(Masters ++ Slaves, os, getpid, []),
  Config1 = proplists:delete(pid, Config),
  Dotter =
    proc_lib:spawn_link(fun Dot() ->
      receive
        stop -> ok
      after 5000 ->
        io:put_chars(user, "."),
        Dot()
      end
    end),
  [{masters, Masters}, {slaves, Slaves}, {pids, Pids}, {dotter, Dotter} | Config1].


end_per_testcase(ping_test, Config) ->
  ?config(dotter, Config) ! stop,
  os:cmd("pkill -CONT -f beam.smp"),
  stop_nodes(?config(slaves, Config)),
  stop_nodes(?config(masters, Config));

end_per_testcase(_, Config) ->
  ?config(dotter, Config) ! stop,
  stop_nodes(?config(slaves, Config)),
  stop_nodes(?config(masters, Config)).

slaves() ->
  %% This is about the highest a Circle-CI machine can handle
  SlaveCount = 20,
  [list_to_atom(lists:flatten(io_lib:format("slave~p", [X]))) || X <- lists:seq(1, SlaveCount)].

masters() ->
  [master1, master2].

ci() ->
  case os:getenv("CIRCLECI") of
    false ->
      false;
    _ ->
      true
  end.

%% Circle-CI can be a little slow to start slaves
%% So we're bumping the boot time out to deal with that.
boot_timeout() ->
  case ci() of
    false ->
      30;
    true ->
      60
  end.

start_nodes() ->
  Timeout = boot_timeout(),
  Results = rpc:pmap({ct_slave, start}, [[{monitor_master, true},
    {boot_timeout, Timeout}, {init_timeout, Timeout}, {startup_timeout, Timeout},
    {erl_flags, "-connect_all false"}]], masters() ++ slaves()),
  ct:pal("Starting nodes: ~p", [Results]),
  Nodes = [NodeName || {ok, NodeName} <- Results],
  {Masters, Slaves} = lists:split(length(masters()), Nodes),
  CodePath = code:get_path(),
  Handlers = [
    {lager_console_backend, debug},
    {lager_file_backend, [{file, "error.log"}, {level, error}]},
    {lager_file_backend, [{file, "console.log"}, {level, debug},
      {formatter, lager_default_formatter},
      {formatter_config, [
        node, ": ", time, " [", severity, "] ", pid, " (", module, ":", function, ":", line, ")", " ", message, "\n"
      ]}
    ]},
    {lager_common_test_backend, debug}
  ],
  rpc:multicall(Nodes, code, add_pathsa, [CodePath]),
  rpc:multicall(Nodes, application, set_env, [lager, handlers, Handlers, [{persistent, true}]]),
  rpc:multicall(Nodes, application, ensure_all_started, [lager]),
  {_, []} = rpc:multicall(Masters, application, set_env, [lashup, contact_nodes, Masters]),
  {_, []} = rpc:multicall(Slaves, application, set_env, [lashup, contact_nodes, Masters]),

  {Masters, Slaves}.

%% Sometimes nodes stick around on Circle-CI
%% TODO: Figure out why and troubleshoot
maybe_kill(Node) ->
  case ci() of
    true ->
      Command = io_lib:format("pkill -9 -f ~s", [Node]),
      os:cmd(Command);
    false ->
      ok
  end.

%% Borrowed from the ct_slave module
do_stop(ENode) ->
  Cover = stop_cover_enode(ENode),
  spawn(ENode, init, stop, []),
  case wait_for_node_dead(ENode, 60) of
    {ok, ENode} ->
      maybe_signal_cover_master(ENode, Cover),
      {ok, ENode};
    Error ->
      Error
  end.

stop_cover_enode(ENode) ->
  case test_server:is_cover() of
    true ->
      Main = cover:get_main_node(),
      rpc:call(Main, cover, flush, [ENode]),
      {true, Main};
    false ->
      {false, undefined}
  end.

%% To avoid that cover is started again if a node
%% with the same name is started later.
maybe_signal_cover_master(ENode, {true, MainCoverNode}) ->
  rpc:call(MainCoverNode, cover, stop, [ENode]);
maybe_signal_cover_master(_, {false, _}) ->
  ok.

% wait until timeout N seconds until node is disconnected
% relies on disterl to tell us if a node has died
% Maybe we should net_adm:ping?
wait_for_node_dead(Node, 0) ->
  {error, stop_timeout, Node};
wait_for_node_dead(Node, N) ->
  timer:sleep(1000),
  case lists:member(Node, nodes()) of
    true ->
      wait_for_node_dead(Node, N - 1);
    false ->
      {ok, Node}
  end.

stop_nodes(Nodes) ->
  StoppedResult = [do_stop(Node) || Node <- Nodes],
  ct:pal("Stopped result: ~p", [StoppedResult]),
  [maybe_kill(Node) || Node <- Nodes].


hyparview_test(Config) ->
  AllNodes = ?config(slaves, Config) ++ ?config(masters, Config),
  application:ensure_all_started(lager),
  _Status = rpc:multicall(?config(masters, Config), application, ensure_all_started, [lashup]),
  rpc:multicall(?config(slaves, Config), application, ensure_all_started, [lashup]),
  LeftOverTime = wait_for_convergence(600000, 5000, AllNodes),
  ct:pal("Converged in ~p milliseconds", [600000 - LeftOverTime]),
  ok.

hyparview_random_kill_test(Config) ->
  ct:pal("Starting random kill test"),
  AllNodes = ?config(slaves, Config) ++ ?config(masters, Config),
  application:ensure_all_started(lager),
  _Status = rpc:multicall(?config(masters, Config), application, ensure_all_started, [lashup]),
  rpc:multicall(?config(slaves, Config), application, ensure_all_started, [lashup]),
  LeftOverTime = wait_for_convergence(600000, 5000, AllNodes),
  ct:pal("Converged in ~p milliseconds", [600000 - LeftOverTime]),
  kill_nodes(Config, length(AllNodes) * 2),
  LeftOverTime2 = wait_for_convergence(600000, 5000, AllNodes),
  ct:pal("ReConverged in ~p milliseconds", [600000 - LeftOverTime2]),
  ok.

kill_nodes(_, 0) ->
  ok;
kill_nodes(Config, Remaining) ->
  AllNodes = ?config(slaves, Config) ++ ?config(masters, Config),
  Idx = rand:uniform(length(AllNodes)),
  Node = lists:nth(Idx, AllNodes),
  ct:pal("Killing node: ~p", [Node]),
  RemotePid = rpc:call(Node, erlang, whereis, [lashup_hyparview_membership]),
  exit(RemotePid, kill),
  timer:sleep(5000),
  kill_nodes(Config, Remaining - 1).

% @doc how long to wait between each ping unreachability test, in ms
%% We want to do 1 minute on CI
%% And 5 seconds on a local test (for speed)

ping_wait_time() ->
  case ci() of
    true ->
      60000;
    false ->
      5000
  end.

ping_test(Config) ->
  hyparview_test(Config),
  timer:sleep(60000),
  ok = stop_start_nodes(Config, 10),
  ok.

stop_start_nodes(_, 0) ->
  ok;
stop_start_nodes(Config, Remaining) ->
  AllNodes = ?config(slaves, Config) ++ ?config(masters, Config),
  KillIdx = rand:uniform(length(AllNodes)),
  KillNode = lists:nth(KillIdx, AllNodes),
  RestNodes = lists:delete(KillNode, AllNodes),
  KillNodePid = rpc:call(KillNode, os, getpid, []),
  KillCmd = io_lib:format("kill -STOP ~s", [KillNodePid]),
  ct:pal("Kill: ~s", [os:cmd(KillCmd)]),
  Now = erlang:monotonic_time(),
  wait_for_unreachability(KillNode, RestNodes, Now),
  Now2 = erlang:monotonic_time(),
  DetectTime = erlang:convert_time_unit(Now2 - Now, native, milli_seconds),
  ct:pal("Failure detection in ~p ms", [DetectTime]),
  UnKillCmd = io_lib:format("kill -CONT ~s", [KillNodePid]),
  ct:pal("UnKill: ~s", [os:cmd(UnKillCmd)]),
  wait_for_convergence(600000, 5000, AllNodes),
  timer:sleep(ping_wait_time()),
  stop_start_nodes(Config, Remaining - 1).


wait_for_unreachability(KillNode, RestNodes, Now) ->
  Idx = rand:uniform(length(RestNodes)),
  Node = lists:nth(Idx, RestNodes),
  Now2 = erlang:monotonic_time(),
  case erlang:convert_time_unit(Now2 - Now, native, seconds) of
    Time when Time > 10 ->
      exit(too_much_time);
    _ ->
      case rpc:call(Node, lashup_gm_route, path_to, [KillNode]) of
        false ->
          ok;
        Else ->
          ct:pal("Node still reachable: ~p", [Else]),
          timer:sleep(100),
          wait_for_unreachability(KillNode, RestNodes, Now)
      end
  end.


failure_test0(Config) ->
  failure_test(Config, 0).

failure_test60(Config) ->
  failure_test(Config, 60000).

failure_test120(Config) ->
  failure_test(Config, 120000).

failure_test300(Config) ->
  failure_test(Config, 300000).

failure_test(Config, Time) ->
  hyparview_test(Config),
  ct:pal("Testing failure conditions"),
  Nodes = ?config(slaves, Config) ++ ?config(masters, Config),
  N = round(length(Nodes) / 2),
  {Nodes1, Nodes2} = lists:split(N, Nodes),
  ct:pal("Splitting networks"),
  rpc:multicall(Nodes1, net_kernel, allow, [[node() | Nodes1]]),
  rpc:multicall(Nodes2, net_kernel, allow, [[node() | Nodes2]]),
  lists:foreach(fun(Node) -> rpc:multicall(Nodes1, erlang, disconnect_node, [Node]) end, Nodes2),
  lists:foreach(fun(Node) -> rpc:multicall(Nodes2, erlang, disconnect_node, [Node]) end, Nodes1),

  ct:pal("Allowing either side to converge independently"),
  wait_for_convergence(600000, 5000, Nodes, 2),
  timer:sleep(Time),
  Healing = rpc:multicall(Nodes, net_kernel, allow, [[node() | Nodes]]),
  ct:pal("Healing networks: ~p", [Healing]),
  LeftOverTime = wait_for_convergence(600000, 5000, Nodes),
  ct:pal("Converged in ~p milliseconds", [600000 - LeftOverTime]),
  ok.



wait_for_convergence(TotalTime, Interval, Nodes) ->
  wait_for_convergence(TotalTime, Interval, Nodes, 1).

wait_for_convergence(TotalTime, Interval, Nodes, Size) when TotalTime > 0 ->
  timer:sleep(Interval),
  case check_graph(Nodes, Size) of
    true ->
      TotalTime;
    false ->
      ct:pal("Unconverged at: ~p remaining~n", [TotalTime]),
      wait_for_convergence(TotalTime - Interval, Interval, Nodes, Size)
  end;

wait_for_convergence(_TotalTime, _Interval, Nodes, _Size) ->
  {Replies, _} = gen_server:multi_call(Nodes, lashup_hyparview_membership, get_active_view, 60000),
  ActiveViews = lists:flatten([ActiveView || {_Node, ActiveView} <- Replies]),
  InitDict = lists:foldl(fun(Node, Acc) -> orddict:update_counter(Node, 0, Acc) end, [], Nodes),
  DictCounted = lists:foldl(fun(Node, Acc) -> orddict:update_counter(Node, 1, Acc) end, InitDict, ActiveViews),
  UnconvergedEgress = lists:flatten([ActiveView || {_Node, ActiveView} <- Replies, length(ActiveView) < 3]),
  UnconvergedIngress = orddict:filter(fun(_Key, Value) -> Value == 0 end, DictCounted),
  ct:pal("Unconverged Egress: ~p", [UnconvergedEgress]),
  ct:pal("Unconverged Ingress: ~p", [UnconvergedIngress]),
  ct:fail(never_converged).



check_graph(Nodes, Size) ->
  Digraph = digraph:new(),
  lists:foreach(fun(Node) -> digraph:add_vertex(Digraph, Node) end, Nodes),
  AddEdges =
    fun(Node) ->
      ActiveView = gen_server:call({lashup_hyparview_membership, Node}, get_active_view, 60000),
      lists:foreach(fun(V2) -> digraph:add_edge(Digraph, Node, V2) end, ActiveView)
    end,
  lists:foreach(AddEdges, Nodes),
  Components = digraph_utils:strong_components(Digraph),
  ct:pal("Components: ~p~n", [Components]),
  digraph:delete(Digraph),
  length(Components) == Size.



mc_test(Config) ->
  hyparview_test(Config),
  AllNodes = ?config(slaves, Config) ++ ?config(masters, Config),
  {_, []} = rpc:multicall(AllNodes, application, set_env, [lashup, max_mc_replication, ?MAX_MC_REPLICATION]),
  timer:sleep(60000), %% Let things settle out
  [Node1, Node2, Node3] = choose_nodes(AllNodes, 3),
  %% Test general messaging
  {ok, Topic1RefNode1} = lashup_gm_mc_events:remote_subscribe(Node1, [topic1]),
  R1 = make_ref(),
  rpc:call(Node2, lashup_gm_mc, multicast, [topic1, R1, [record_route]]),
  true = ?MAX_MC_REPLICATION == expect_replies(Topic1RefNode1, R1),
  timer:sleep(5000),
  %% Make sure that we don't see "old" events
  {ok, Topic1RefNode3} = lashup_gm_mc_events:remote_subscribe(Node3, [topic1]),
  true = 0 == expect_replies(Topic1RefNode3, R1),
  %% Test only nodes
  R2 = make_ref(),
  rpc:call(Node2, lashup_gm_mc, multicast, [topic1, R2, [{only_nodes, [Node3]}]]),
  true = ?MAX_MC_REPLICATION == expect_replies(Topic1RefNode3, R2),
  true = 0 == expect_replies(Topic1RefNode1, R2),
  R3 = make_ref(),
  rpc:call(Node2, lashup_gm_mc, multicast, [topic1, R3, [{fanout, 1}]]),
  true = 1 == expect_replies(Topic1RefNode1, R3),
  ok.


expect_replies(Reference, Payload) ->
  expect_replies(Reference, Payload, 0).

expect_replies(Reference, Payload, Count) ->
  receive
    {lashup_gm_mc_event, Event = #{ref := Reference, payload := Payload}} ->
      ct:pal("Received event (~p): ~p", [Count + 1, Event]),
      expect_replies(Reference, Payload, Count + 1)
  after 5000 ->
    Count
  end.

choose_nodes(Nodes, Count) ->
  choose_nodes(Nodes, Count, []).

choose_nodes(_, 0, Acc) ->
  Acc;
choose_nodes(Nodes, Count, Acc) ->
  Idx = rand:uniform(length(Nodes)),
  Node = lists:nth(Idx, Nodes),
  Nodes1 = lists:delete(Node, Nodes),
  choose_nodes(Nodes1, Count - 1, [Node | Acc]).

%% TODO:
%% -Add Kill
%% -Add concurrency
kv_test(Config) ->
  AllNodes = ?config(slaves, Config) ++ ?config(masters, Config),
  application:ensure_all_started(lager),
  _Status = rpc:multicall(?config(masters, Config), application, ensure_all_started, [lashup]),
  rpc:multicall(?config(slaves, Config), application, ensure_all_started, [lashup]),
  %% Normal value is 5 minutes, let's not wait that long
  {_, []} = rpc:multicall(AllNodes, application, set_env, [lashup, aae_interval, 30000]),
  {_, []} = rpc:multicall(AllNodes, application, set_env, [lashup, key_aae_interval, 30000]),
  Update1 = {update, [{update, {test_counter, riak_dt_pncounter}, {increment, 5}}]},
  [rpc:call(Node, lashup_kv, request_op, [Node, Update1]) || Node <- AllNodes],
  [rpc:call(Node, lashup_kv, request_op, [god_counter, Update1]) || Node <- AllNodes],
  LeftOverTime1 = wait_for_convergence(600000, 5000, AllNodes),
  ct:pal("Converged in ~p milliseconds", [600000 - LeftOverTime1]),
  LeftOverTime2 = wait_for_consistency(600000, 5000, AllNodes),
  ct:pal("Consistency acheived  in ~p milliseconds", [600000 - LeftOverTime2]),
  ok.


wait_for_consistency(TotalTime, Interval, Nodes) when TotalTime > 0 ->
  timer:sleep(Interval),
  case check_nodes_for_consistency(Nodes, Nodes, 0) of
    true ->
      TotalTime;
    false ->
      ct:pal("Inconsistent at: ~p remaining~n", [TotalTime]),
      wait_for_consistency(TotalTime - Interval, Interval, Nodes)
  end;
wait_for_consistency(_TotalTime, _Interval, _Nodes) ->
  ct:fail(never_consistent).


check_nodes_for_consistency([], _AllNodes, 0) ->
  true;
check_nodes_for_consistency([], _AllNodes, _) ->
  false;
check_nodes_for_consistency([Node | Rest], AllNodes, InconsistentNodeCount) ->
  {ConsistentKeys, InconsistentKeys} =
    lists:partition(
      fun(OtherNode) ->
        rpc:call(Node, lashup_kv, value, [OtherNode]) == [{{test_counter, riak_dt_pncounter}, 5}]
      end,
      AllNodes
    ),
  ExpectedGodCounterValue = length(AllNodes) * 5,
  {ConsistentKeys1, InconsistentKeys1} =
    case rpc:call(Node, lashup_kv, value, [god_counter]) of
      [{{test_counter, riak_dt_pncounter}, ExpectedGodCounterValue}] ->
        {[god_counter|ConsistentKeys], InconsistentKeys};
      GodCounter ->
        ct:pal("God counter (~p): ~p", [Node, GodCounter]),
        {ConsistentKeys, [god_counter|InconsistentKeys]}
    end,
  ct:pal("Consistent keys (~p): ~p", [Node, ConsistentKeys1]),
  ct:pal("Inconsistent keys (~p): ~p", [Node, InconsistentKeys1]),

  case InconsistentKeys1 of
    [] ->
      check_nodes_for_consistency(Rest, AllNodes, InconsistentNodeCount);
    _ ->
      check_nodes_for_consistency(Rest, AllNodes, InconsistentNodeCount + 1)
  end.

