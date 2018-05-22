-module(lashup_gm_route_SUITE).
-author("sdhillon").

-include_lib("common_test/include/ct.hrl").

%% API
-export([all/0]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Testcases
-export([benchmark/1, basic_events/1, busy_wait_events/1]).

all() -> [benchmark, basic_events, busy_wait_events].

init_per_testcase(_TestCase, Config) ->
    application:ensure_all_started(lager),
    {ok, _} = lashup_gm_route:start_link(),
    {ok, _} = lashup_gm_route_events:start_link(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    gen_event:stop(lashup_gm_route_events),
    lashup_gm_route:stop().

%% Create a list of X nodes
%% Until every node has N adjacencies, choose a node another node from the list and make then adjacent
generate_graph(Nodes) ->
    Tuple = erlang:make_tuple(Nodes, []),
    populate_graph(1, Tuple).

find_candidates(N, Tuple, _Exempt, Acc) when N > size(Tuple) ->
    Acc;
find_candidates(N, Tuple, Exempt, Acc) when N == Exempt ->
    find_candidates(N + 1, Tuple, Exempt, Acc);
find_candidates(N, Tuple, Exempt, Acc) when length(element(N, Tuple)) < 5 ->
    case ordsets:is_element(Exempt, element(N, Tuple)) of
        true ->
            find_candidates(N + 1, Tuple, Exempt, Acc);
        false ->
            find_candidates(N + 1, Tuple, Exempt, [N|Acc])
    end;
find_candidates(N, Tuple, Exempt, Acc) ->
    find_candidates(N + 1, Tuple, Exempt, Acc).

populate_graph(N, Tuple) when N > size(Tuple) ->
    Tuple;
populate_graph(N, Tuple) when length(element(N, Tuple)) < 5 ->
    Candidates = find_candidates(1, Tuple, N, []),
    case Candidates of
        [] ->
            Tuple;
        _ ->
            Candidate = lists:nth(rand:uniform(length(Candidates)), Candidates),
            OldLocalElements = element(N, Tuple),
            OldCandidateElements = element(Candidate, Tuple),
            NewLocalElements = [Candidate|OldLocalElements],
            NewCandidateElements = [N|OldCandidateElements],
            Tuple1 = setelement(N, Tuple, NewLocalElements),
            Tuple2 = setelement(Candidate, Tuple1, NewCandidateElements),
            populate_graph(1, Tuple2)
    end;
populate_graph(N, Tuple)  ->
    populate_graph(N + 1, Tuple).

insert_graph(N, Tuple) when N > size(Tuple) ->
    ok;
insert_graph(N, Tuple) ->
    AdjNodes = [{node, X} || X <- element(N, Tuple)],
    lashup_gm_route:update_node({node, N}, AdjNodes),
    insert_graph(N + 1, Tuple).

get_tree() ->
    {Val, _} = timer:tc(lashup_gm_route, get_tree, [{node, 10}, 50000]),
    timer:sleep(500),
    ct:pal("Time: ~p", [Val]).

benchmark(_Config) ->
    Graph = generate_graph(1000),
    %eprof:start(),
    %eprof:start_profiling([whereis(lashup_gm_route)]),
    %fprof:start(),
    insert_graph(1, Graph),
    %fprof:trace([start, {file, "fprof.trace"}, verbose, {procs, [whereis(lashup_gm_route)]}]),
    get_tree(),
    lashup_gm_route:update_node(foo, [1]),
    get_tree(),
    lashup_gm_route:update_node(foo, [2]),
    get_tree(),
    lashup_gm_route:update_node(foo, [1]),
    get_tree(),
    lashup_gm_route:update_node(foo, [2]),
    get_tree(),
    lashup_gm_route:update_node(foo, [1]),
    get_tree().
    %fprof:trace([stop]),
    %fprof:profile({file, "fprof.trace"}),
    %ct:pal("Time: ~p", [Val]).
    %fprof:analyse([totals, {dest, "fprof.analysis"}]).

% eprof:stop_profiling(),
   % eprof:log("eprof.log"),
   % eprof:analyze().

basic_events(_Config) ->
    lashup_gm_route:update_node(node(), [1]),
    lashup_gm_route:update_node(500, [150]),
    lashup_gm_route:update_node(500, [200]),
    {ok, Ref} = lashup_gm_route_events:subscribe(),
    true = (count_events(Ref) > 0),
    lashup_gm_route:update_node(500, [150]),
    1 = count_events(Ref).

count_events(Ref) -> count_events(Ref, 0).

count_events(Ref, Acc) ->
    receive
        {lashup_gm_route_events, _Event = #{ref := Ref}} ->
            count_events(Ref, Acc + 1)
        after 500 ->
            Acc
    end.

busy_wait_events(_Config) ->
    lashup_gm_route:update_node(node(), [1]),
    {ok, Ref} = lashup_gm_route_events:subscribe(),
    lists:foreach(fun(X) -> lashup_gm_route:update_node(1, [X]) end, lists:seq(1, 50)),
    true = (count_events(Ref) < 20),
    timer:sleep(2000),
    lashup_gm_route:update_node(node(), [1, 2]),
    Num = count_events(Ref),
    true = (Num < 5) andalso (Num > 0).
