-module(lashup_hyparview_SUITE).
-author("sdhillon").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([
    all/0,
    init_per_testcase/2, end_per_testcase/2,
    init_per_suite/1, end_per_suite/1
]).

-export([
    hyparview_test/1,
    hyparview_random_kill_test/1,
    ping_test/1,
    failure_test/1,
    mc_test/1,
    kv_test/1
]).

-define(MAX_MC_REPLICATION, 3).

all() -> [
    hyparview_test,
    hyparview_random_kill_test,
    ping_test,
    failure_test,
    mc_test,
    kv_test
].

-define(MASTERS, [master1, master2, master3]).
-define(AGENTS, [agent1, agent2, agent3, agent4, agent5, agent6, agent7]).

init_per_suite(Config) ->
    os:cmd(os:find_executable("epmd") ++ " -daemon"),
    {ok, Hostname} = inet:gethostname(),
    case net_kernel:start([list_to_atom("runner@" ++ Hostname), shortnames]) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,
    [{hostname, Hostname}| Config].

end_per_suite(Config) ->
    net_kernel:stop(),
    Config.

init_per_testcase(TestCase, Config) ->
    ct:pal("Starting Testcase: ~p", [TestCase]),
    Nodes = start_nodes(?MASTERS ++ ?AGENTS),
    configure_nodes(Nodes, masters(Nodes)),
    [{nodes, Nodes} | Config].

end_per_testcase(_, Config) ->
    stop_nodes(?config(nodes, Config)),
    %% remove lashup and mnesia directory
    os:cmd("rm -rf *@" ++ ?config(hostname, Config)),
    Config.

masters(Nodes) ->
    element(1, lists:split(length(?MASTERS), Nodes)).

agents(Nodes) ->
	element(2, lists:split(length(?MASTERS), Nodes)).

start_nodes(Nodes) ->
    Opts = [{monitor_master, true}, {erl_flags, "-connect_all false"}],
    Result = [ct_slave:start(Node, Opts) || Node <- Nodes],
    NodeNames = [NodeName || {ok, NodeName} <- Result],
    lists:foreach(fun(Node) -> pong = net_adm:ping(Node) end, NodeNames),
    NodeNames.

configure_nodes(Nodes, Masters) ->
    Env = [lashup, contact_nodes, Masters],
    {_, []} = rpc:multicall(Nodes, code, add_pathsa, [code:get_path()]),
    {_, []} = rpc:multicall(Nodes, application, set_env, Env).

stop_nodes(Nodes) ->
    StoppedResult = [ct_slave:stop(Node) || Node <- Nodes],
    lists:foreach(fun(Node) -> pang = net_adm:ping(Node) end, Nodes),
    ct:pal("Stopped result: ~p", [StoppedResult]).

hyparview_test(Config) ->
    Nodes = ?config(nodes, Config),
    {_, []} = rpc:multicall(Nodes, application, ensure_all_started, [lashup]),
    LeftOverTime = wait_for_convergence(60000, 5000, Nodes),
    ct:pal("Converged in ~p milliseconds", [60000 - LeftOverTime]),
    ok.

hyparview_random_kill_test(Config) ->
    Nodes = ?config(nodes, Config),
    hyparview_test(Config),
    kill_nodes(Nodes, length(Nodes) * 2),
    LeftOverTime = wait_for_convergence(60000, 5000, Nodes),
    ct:pal("ReConverged in ~p milliseconds", [60000 - LeftOverTime]),
    ok.

kill_nodes(_, 0) ->
    ok;
kill_nodes(Nodes, Remaining) ->
    Idx = rand:uniform(length(Nodes)),
    Node = lists:nth(Idx, Nodes),
    ct:pal("Killing node: ~p", [Node]),
    RemotePid = rpc:call(Node, erlang, whereis, [lashup_hyparview_membership]),
    exit(RemotePid, kill),
    timer:sleep(5000),
    kill_nodes(Nodes, Remaining - 1).

ping_test(Config) ->
    hyparview_test(Config),
    ok = stop_start_nodes(?config(nodes, Config), 10),
    ok.

stop_start_nodes(_, 0) ->
    ok;
stop_start_nodes(Nodes, Remaining) ->
    Node = random_node(Nodes),
    ct:pal("Stopping: ~s", [Node]),
    stop_nodes([Node]),
    RestNodes = lists:delete(Node, Nodes),
    Now = erlang:monotonic_time(),
    wait_for_unreachability(Node, RestNodes, Now),
    Now2 = erlang:monotonic_time(),
    DetectTime = erlang:convert_time_unit(Now2 - Now, native, milli_seconds),
    ct:pal("Failure detection in ~p ms", [DetectTime]),
    start_nodes([Node]),
    configure_nodes([Node], masters(Nodes)),
    rpc:call(Node, application, ensure_all_started, [lashup]),
    ct:pal("Starting: ~s", [Node]),
    wait_for_convergence(60000, 5000, Nodes),
    stop_start_nodes(Nodes, Remaining - 1).

random_node(Nodes) ->
    Idx = rand:uniform(length(Nodes)),
    lists:nth(Idx, Nodes).

wait_for_unreachability(DstNode, RestNodes, Now) ->
    SrcNode = random_node(RestNodes),
    Now2 = erlang:monotonic_time(),
    case erlang:convert_time_unit(Now2 - Now, native, seconds) of
        Time when Time > 10 ->
            exit(too_much_time);
        _ ->
            case rpc:call(SrcNode, lashup_gm_route, path_to, [DstNode]) of
                false ->
                    ok;
                Else ->
                    ct:pal("Node still reachable: ~p", [Else]),
                    timer:sleep(100),
                    wait_for_unreachability(DstNode, RestNodes, Now)
            end
    end.


failure_test(Config) ->
    hyparview_test(Config),
    ct:pal("Testing failure conditions"),
    Nodes = ?config(nodes, Config),
    {Nodes1, Nodes2} = split(masters(Nodes), agents(Nodes)),
    ct:pal("Splitting networks ~p ~p", [Nodes1, Nodes2]),
    {_, []} = rpc:multicall(Nodes1, net_kernel, allow, [[node() | Nodes1]]),
    {_, []} = rpc:multicall(Nodes2, net_kernel, allow, [[node() | Nodes2]]),
    lists:foreach(fun(Node) ->
        {_, []} = rpc:multicall(Nodes1, erlang, disconnect_node, [Node])
    end, Nodes2),
    lists:foreach(fun(Node) ->
        {_, []} = rpc:multicall(Nodes2, erlang, disconnect_node, [Node])
    end, Nodes1),
    ct:pal("Allowing either side to converge independently"),
    wait_for_convergence(60000, 5000, Nodes, 2),
    Healing = rpc:multicall(Nodes, net_kernel, allow, [[node() | Nodes]]),
    ct:pal("Healing networks: ~p", [Healing]),
    LeftOverTime = wait_for_convergence(60000, 5000, Nodes),
    ct:pal("Converged in ~p milliseconds", [60000 - LeftOverTime]),
    ok.

split(Masters, Agents) ->
    A = round(length(Agents) / 2),
    {Agents1, Agents2} = lists:split(A, Agents),
    M = round(length(Masters) / 2),
    {Masters1, Masters2} = lists:split(M, Masters),
    {Masters1 ++ Agents1, Masters2 ++ Agents2}.

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
    InitDict = lists:foldl(fun(Node, Acc) ->
                   orddict:update_counter(Node, 0, Acc)
               end, [], Nodes),
    DictCounted = lists:foldl(fun(Node, Acc) ->
                      orddict:update_counter(Node, 1, Acc)
                  end, InitDict, ActiveViews),
    Unconverged = orddict:filter(fun(_Key, Value) ->
                      Value == 0 
                  end, DictCounted),
    ct:pal("Unconverged: ~p", [Unconverged]),
    ct:fail(never_converged).

check_graph(Nodes, Size) ->
    Digraph = digraph:new(),
    lists:foreach(fun(Node) -> digraph:add_vertex(Digraph, Node) end, Nodes),
    lists:foreach(fun(Node) ->
        ActiveView = gen_server:call({lashup_hyparview_membership, Node}, get_active_view, 60000),
        lists:foreach(fun(V2) -> digraph:add_edge(Digraph, Node, V2) end, ActiveView)
    end, Nodes),
    Components = digraph_utils:strong_components(Digraph),
    ct:pal("Components: ~p~n", [Components]),
    digraph:delete(Digraph),
    length(Components) == Size.

mc_test(Config) ->
    hyparview_test(Config),
    Nodes = ?config(nodes, Config),
    Env = [lashup, max_mc_replication, ?MAX_MC_REPLICATION],
    {_, []} = rpc:multicall(Nodes, application, set_env, Env),
    timer:sleep(60000), %% Let things settle out
    [Node1, Node2, Node3] = choose_nodes(Nodes, 3),
    %% Test general messaging
    {ok, Topic1RefNode1} = lashup_gm_mc_events:remote_subscribe(Node1, [topic1]),
    R1 = make_ref(),
    rpc:call(Node2, lashup_gm_mc, multicast, [topic1, R1]),
    ?assertEqual(?MAX_MC_REPLICATION, expect_replies(Topic1RefNode1, R1)),
    timer:sleep(5000),
    %% Make sure that we don't see "old" events
    {ok, Topic1RefNode3} = lashup_gm_mc_events:remote_subscribe(Node3, [topic1]),
    ?assertEqual(0, expect_replies(Topic1RefNode3, R1)),
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
    Nodes = ?config(nodes, Config),
    rpc:multicall(Nodes, application, ensure_all_started, [lashup]),
    %% Normal value is 5 minutes, let's not wait that long
    {_, []} = rpc:multicall(Nodes, application, set_env, [lashup, aae_interval, 30000]),
    {_, []} = rpc:multicall(Nodes, application, set_env, [lashup, key_aae_interval, 30000]),
    Update1 = {update, [{update, {test_counter, riak_dt_pncounter}, {increment, 5}}]},
    [rpc:call(Node, lashup_kv, request_op, [Node, Update1]) || Node <- Nodes],
    [rpc:call(Node, lashup_kv, request_op, [god_counter, Update1]) || Node <- Nodes],
    LeftOverTime1 = wait_for_convergence(60000, 5000, Nodes),
    ct:pal("Converged in ~p milliseconds", [60000 - LeftOverTime1]),
    LeftOverTime2 = wait_for_consistency(90000, 5000, Nodes),
    ct:pal("Consistency acheived  in ~p milliseconds", [90000 - LeftOverTime2]),
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

check_nodes_for_consistency([], _, 0) ->
    true;
check_nodes_for_consistency([], _, _) ->
    false;
check_nodes_for_consistency([Node | Rest], Nodes, InconsistentNodeCount) ->
    {ConsistentKeys, InconsistentKeys} =
        lists:partition(fun(OtherNode) ->
            Value = rpc:call(Node, lashup_kv, value, [OtherNode]),
            Value == [{{test_counter, riak_dt_pncounter}, 5}]
        end, Nodes),
    ExpectedGodCounterValue = length(Nodes) * 5,
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
            check_nodes_for_consistency(Rest, Nodes, InconsistentNodeCount);
        _ ->
            check_nodes_for_consistency(Rest, Nodes, InconsistentNodeCount + 1)
    end.
