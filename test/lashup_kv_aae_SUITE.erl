-module(lashup_kv_aae_SUITE).

-compile({parse_transform, lager_transform}).

-include_lib("common_test/include/ct.hrl").

-export([
    all/0,
    init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    lashup_kv_aae_test/1
]).

-define(MASTERS, [master1]).
-define(AGENTS, [agent1, agent2]).

-define(WAIT, 60000).

init_per_suite(Config) ->
    os:cmd(os:find_executable("epmd") ++ " -daemon"),
    {ok, Hostname} = inet:gethostname(),
    case net_kernel:start([list_to_atom("runner@" ++ Hostname), shortnames]) of
      {ok, _} -> ok;
      {error, {already_started, _}} -> ok
    end,
    [{hostname, Hostname} | Config].

end_per_suite(Config) ->
    application:stop(lashup),
    net_kernel:stop(),
    Config.

all() ->
    [lashup_kv_aae_test].

init_per_testcase(TestCaseName, Config) ->
    ct:pal("Starting Testcase: ~p", [TestCaseName]),
    Nodes = start_nodes(?MASTERS ++ ?AGENTS),
    configure_nodes(Nodes, masters(Nodes)),
    [{nodes, Nodes} | Config].

end_per_testcase(_, Config) ->
    stop_nodes(?config(nodes, Config)),
    %% remove lashup and mnesia directory
    %%os:cmd("rm -rf *@" ++ ?config(hostname, Config)),
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

lashup_kv_aae_test(Config) ->
    %% Insert a record in lashup
    Nodes = ?config(nodes, Config),
    {_, []} = rpc:multicall(Nodes, application, ensure_all_started, [lashup]),
    {_, []} = rpc:multicall(Nodes, application, set_env, [lashup, aae_interval, 20000]),
    {[Master|_], [Agent|_]} = {masters(Nodes), agents(Nodes)},
    SystemTime = erlang:system_time(nano_seconds),
    Val = {update, [{update, {flag, riak_dt_lwwreg}, {assign, true, SystemTime}}]},
    {ok, _} = rpc:call(Master, lashup_kv, request_op, [[test], Val]),
    {ok, _} = rpc:call(Master, lashup_kv, request_op, [[test1], Val]),
    timer:sleep(?WAIT), % sleep for aae to kick in
    1 = rpc:call(Master, lashup_kv, read_lclock, [Agent]),
    %% stop Agent
    ct:pal("Stopping agent ~p", [Agent]),
    stop_nodes([Agent]),
    timer:sleep(?WAIT),
    %% Master should reset the clock only after 2 min
    1 = rpc:call(Master, lashup_kv, read_lclock, [Agent]),
    timer:sleep(?WAIT), % wait for 1 more min
    %% Verify that Master resetted the clock for the agent
    -1 = rpc:call(Master, lashup_kv, read_lclock, [Agent]).
