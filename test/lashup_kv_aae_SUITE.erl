-module(lashup_kv_aae_SUITE).

-compile({parse_transform, lager_transform}).

-include_lib("common_test/include/ct.hrl").

-export([
    all/0,
    init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    lashup_kv_aae_test/1
]).

-define(AGENT_COUNT, 2).
-define(MASTER_COUNT, 1).
-define(LASHUPDIR(BaseDir), filename:join([BaseDir, "lashup"])).
-define(MNESIADIR(BaseDir), filename:join([BaseDir, "mnesia"])).

-define(WAIT, 60000).

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
    application:stop(lashup),
    net_kernel:stop(),
    Config.

all() ->
    [lashup_kv_aae_test].

init_per_testcase(TestCaseName, Config) ->
    ct:pal("Starting Testcase: ~p", [TestCaseName]),
    {Masters, Agents} = start_nodes(Config),
    Config0 = proplists:delete(pid, Config),
    [{masters, Masters}, {agents, Agents} | Config0].

end_per_testcase(_, Config) ->
    stop_nodes(?config(agents, Config)),
    stop_nodes(?config(masters, Config)),
    cleanup_files(Config).

cleanup_files(Config) ->
    PrivateDir = ?config(priv_dir, Config),
    os:cmd("rm -rf " ++ ?LASHUPDIR(PrivateDir) ++ "/*"),
    os:cmd("rm -rf " ++ ?MNESIADIR(PrivateDir) ++ "/*").

agents() ->
    [list_to_atom(lists:flatten(io_lib:format("agent~p", [X]))) || X <- lists:seq(1, ?AGENT_COUNT)].

masters() ->
    Start = ?AGENT_COUNT + 1,
    End = ?AGENT_COUNT + ?MASTER_COUNT,
    [list_to_atom(lists:flatten(io_lib:format("master~p", [X]))) || X <- lists:seq(Start, End)].

ci() ->
    case os:getenv("CIRCLECI") of
        false ->
            false;
        _ ->
            true
    end.

%% Circle-CI can be a little slow to start agents
%% So we're bumping the boot time out to deal with that.
boot_timeout() ->
    case ci() of
        false ->
            30;
        true ->
            120
    end.

configure_lashup_dir(Nodes, Config) ->
    PrivateDir = ?config(priv_dir, Config),
    LashupDir = ?LASHUPDIR(PrivateDir),
    ok = filelib:ensure_dir(LashupDir ++ "/"),
    LashupEnv = [lashup, work_dir, LashupDir],
    {_, []} = rpc:multicall(Nodes, application, set_env, LashupEnv).

configure_mnesia_dir(Node, Config) ->
    PrivateDir = ?config(priv_dir, Config),
    MnesiaDir = filename:join(?MNESIADIR(PrivateDir), Node),
    ok = filelib:ensure_dir(MnesiaDir ++ "/"),
    MnesiaEnv = [mnesia, dir, MnesiaDir],
    ok = rpc:call(Node, application, set_env, MnesiaEnv).

start_nodes(Config) ->
    Timeout = boot_timeout(),
    Results = rpc:pmap({ct_slave, start}, [[{monitor_master, true},
        {boot_timeout, Timeout}, {init_timeout, Timeout},
        {startup_timeout, Timeout}, {erl_flags, "-connect_all false"}]],
        masters() ++ agents()),
    io:format("Starting nodes: ~p", [Results]),
    Nodes = [NodeName || {ok, NodeName} <- Results],
    {Masters, Agents} = lists:split(length(masters()), Nodes),
    configure_nodes(Config, Masters, Agents),
    {Masters, Agents}.

configure_nodes(Config, Masters, Agents) ->
    Nodes = Masters ++ Agents,
    Handlers = lager_config_handlers(),
    CodePath = code:get_path(),
    rpc:multicall(Nodes, code, add_pathsa, [CodePath]),
    rpc:multicall(Nodes, application, set_env, [lager, handlers, Handlers, [{persistent, true}]]),
    rpc:multicall(Nodes, application, ensure_all_started, [lager]),
    configure_lashup_dir(Nodes, Config),
    lists:foreach(fun(Node) -> configure_mnesia_dir(Node, Config) end, Nodes),
    {_, []} = rpc:multicall(Masters, application, set_env, [lashup, contact_nodes, Masters]),
    {_, []} = rpc:multicall(Agents, application, set_env, [lashup, contact_nodes, Masters]).

lager_config_handlers() ->
    [
        {lager_console_backend, debug},
        {lager_file_backend, [
            {file, "error.log"},
            {level, error}
        ]},
        {lager_file_backend, [
            {file, "console.log"},
            {level, debug},
            {formatter, lager_default_formatter},
            {formatter_config, [
                node, ": ", time,
                " [", severity, "] ", pid,
                " (", module, ":", function, ":", line, ")",
                " ", message, "\n"
            ]}
        ]},
        {lager_common_test_backend, debug}
    ].

stop_nodes(Nodes) ->
    StoppedResult = rpc:pmap({ct_slave, stop}, [], Nodes),
    ct:pal("Stopped result: ~p", [StoppedResult]),
    [maybe_kill(Node) || Node <- Nodes].

%% Sometimes nodes stick around on Circle-CI
maybe_kill(Node) ->
    case ci() of
        true ->
            Command = io_lib:format("pkill -9 -f ~s", [Node]),
            os:cmd(Command);
        false ->
            ok
    end.

lashup_kv_aae_test(Config) ->
    %% Insert a record in lashup
    AllNodes = ?config(agents, Config) ++ ?config(masters, Config),
    rpc:multicall(AllNodes, application, ensure_all_started, [lashup]),
    [Master|_] = ?config(masters, Config),
    [Agent|_] = ?config(agents, Config),
    SystemTime = erlang:system_time(nano_seconds),
    Val = {update, [{update, {flag, riak_dt_lwwreg}, {assign, true, SystemTime}}]},
    {ok, _} = rpc:call(Master, lashup_kv, request_op, [[test], Val]),
    {ok, _} = rpc:call(Master, lashup_kv, request_op, [[test1], Val]),
    timer:sleep(?WAIT), % sleep for aae to kick in
    1 = rpc:call(Master, lashup_kv, read_lclock, [Agent]),
    %% stop Agent
    stop_nodes([Agent]),
    timer:sleep(?WAIT),
    %% Master should reset the clock only after 2 min
    1 = rpc:call(Master, lashup_kv, read_lclock, [Agent]),
    timer:sleep(?WAIT), % wait for 1 more min
    %% Verify that Master resetted the clock for the agent
    -1 = rpc:call(Master, lashup_kv, read_lclock, [Agent]).
