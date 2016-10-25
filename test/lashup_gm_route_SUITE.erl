%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 25. Oct 2016 1:53 AM
%%%-------------------------------------------------------------------
-module(lashup_gm_route_SUITE).
-author("sdhillon").

-include_lib("common_test/include/ct.hrl").

%% API
-export([all/0]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Testcases
-export([benchmark/1]).

all() -> [benchmark].

init_per_testcase(_TestCase, Config) ->
    {ok, _Pid} = lashup_gm_route:start_link(),
    Config.

end_per_testcase(_TestCase, _Config) ->
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

benchmark(_Config) ->
    Graph = generate_graph(1000),
    insert_graph(1, Graph),
    {Val, _} = timer:tc(lashup_gm_route, get_tree, [{node, 10}]),
    ct:pal("Time: ~p", [Val]).