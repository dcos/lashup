%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 30. May 2016 4:05 PM
%%%-------------------------------------------------------------------
-module(lashup_bloom).
-author("sdhillon").


-ifdef(TEST).
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(lashup_bloom, {
    hash_functions :: non_neg_integer(),
    bits :: tuple()
}).
-type filter() :: #lashup_bloom{}.
-export_type([filter/0]).

-define(SEED, 102551).
-define(D, 0.4804530139182014).
-define(MAX_HASH, 4294967296).
%% API
-export([new/1, add_element/2, has_element/2, calculate_size/2, size/1]).

size(#lashup_bloom{hash_functions = HFs, bits = Bits}) ->
    {erlang:size(Bits), HFs}.

calculate_size(N0, P) ->
    N1 = N0 + 1,
    Bits = ((-1.0 * N1) * math:log(P)) / ?D,
    Words = ceiling(Bits / 32),
    HashFunctions = ceiling((Bits / N1) * math:log(2)),
    {Words, HashFunctions}.

-spec(new({Words :: non_neg_integer(), HashFunctions :: non_neg_integer()}) -> filter()).
new({Words, HashFunctions}) ->
    Bits = erlang:make_tuple(Words, 0),
    #lashup_bloom{bits = Bits, hash_functions = HashFunctions}.

-spec(add_element(Element :: term(), Filter :: filter()) -> filter()).
add_element(Element, Filter) ->
    add_element(Element, Filter, ?SEED, 1).

add_element(_, Filter = #lashup_bloom{hash_functions = HFs}, _, N) when N > HFs ->
    Filter;
add_element(Element, Filter0 = #lashup_bloom{bits = Bits0}, Seed, N) ->
    MaxHash = erlang:size(Bits0) * 32,
    HashN = hash({Seed, Element}, MaxHash),
    ElementNum = 1 + trunc(HashN / 32),
    Bit = HashN rem 32,
    Element0 = erlang:element(ElementNum, Bits0),
    Element1 = Element0 bor (1 bsl Bit),
    Bits1 = setelement(ElementNum, Bits0, Element1),
    Filter1 = Filter0#lashup_bloom{bits = Bits1},
    add_element(Element, Filter1, next_seed(Seed), N + 1).

-spec(has_element(Element :: term(), Filter :: filter()) -> boolean()).
has_element(Element, Filter = #lashup_bloom{bits = Bits, hash_functions = HFs}) ->
    TmpFilter0 = new({erlang:size(Bits), HFs}),
    TmpFilter1 = add_element(Element, TmpFilter0),
    has_element(TmpFilter1, Filter, 1).

has_element(_ElementFilter = #lashup_bloom{bits = Bits}, _ExistingFilter, N) when N > erlang:size(Bits) ->
    true;
has_element(ElementFilter = #lashup_bloom{bits = ElementBits},
        ExistingFilter = #lashup_bloom{bits = ExistingBits}, N) ->
    ExistInt = element(N, ExistingBits),
    ElementInt = element(N, ElementBits),
    case (ExistInt band ElementInt) of
        ElementInt ->
            has_element(ElementFilter, ExistingFilter, N  + 1);
        _ ->
            false
    end.



hash(X, Max) when is_binary(X) ->
    erlang:phash2(X, Max);
hash(X, Max) ->
    hash(term_to_binary(X), Max).

next_seed(X) ->
    erlang:phash2(X, ?MAX_HASH).

ceiling(X) when X < 0 ->
    trunc(X);
ceiling(X) ->
    T = trunc(X),
    case X - T of
        0.0 -> T;
        0 -> T;
        _ -> T + 1
    end.

-ifdef(TEST).
basic_test() ->
    Size = calculate_size(10000, 0.01),
    New0 = new(Size),
    New1 = add_element(cat, New0),
    ?assert(has_element(cat, New1)),
    ?assertNot(has_element(notcat, New1)).

proper_test_() ->
    [] = proper:module(?MODULE, [{to_file, user}, {numtests, 10000}]).

prop_works() ->
    ?FORALL(
        Element,
        term(),
        begin
            Size = calculate_size(1000, 0.01),
            New0 = new(Size),
            New1 = add_element(Element, New0),
            has_element(Element, New1)
        end
    ).


term_list() ->
    list(term()).

prop_works2() ->
    ?FORALL(
        Elements,
        term_list(),
        begin
            Size = calculate_size(1000, 0.01),
            New0 = new(Size),
            New1 = lists:foldl(fun add_element/2, New0, Elements),
            lists:all(fun(Element) -> has_element(Element, New1) end, Elements)
        end
    ).
-endif.