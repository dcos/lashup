-module(lashup_utils).
-author("sdhillon").

-include_lib("kernel/include/file.hrl").

%% API
-export([
  seed/0,
  shuffle_list/2,
  new_window/1,
  add_tick/1,
  count_ticks/1,
  compare_vclocks/2,
  subtract/2,
  shuffle_list/1,
  replace_file/2,
  read_file/1
]).

-export_type([window/0]).

-record(window, {
  samples = [] :: list(integer()),
  window_time = 0 :: non_neg_integer()}).
-type window() :: #window{}.


-spec(seed() -> rand:state()).
seed() ->
  rand:seed(exsplus).

-spec shuffle_list(List, Seed :: rand:state()) -> List1 when
  List :: [T, ...],
  List1 :: [T, ...],
  T :: term().
shuffle_list(List, FixedSeed) ->
  {_, PrefixedList} =
    lists:foldl(fun(X, {SeedState, Acc}) ->
      {N, SeedState1} = rand:uniform_s(1000000, SeedState),
      {SeedState1, [{N, X} | Acc]}
                end,
      {FixedSeed, []},
      List),
  PrefixedListSorted = lists:sort(PrefixedList),
  [Value || {_N, Value} <- PrefixedListSorted].

-spec shuffle_list(List) -> List1 when
  List :: [T, ...],
  List1 :: [T, ...],
  T :: term().
shuffle_list(List) ->
  PrefixedList = [{rand:uniform(1000000), Item} || Item <- List],
  PrefixedListSorted = lists:sort(PrefixedList),
  [Value || {_N, Value} <- PrefixedListSorted].

-spec(new_window(WindowTime :: non_neg_integer()) -> window()).
new_window(WindowTime) ->
  #window{window_time = WindowTime}.

-spec(add_tick(window()) -> window()).
add_tick(Window = #window{window_time = WindowTime, samples = Samples}) ->
  Sample = erlang:monotonic_time(milli_seconds),
  Now = erlang:monotonic_time(milli_seconds),
  Samples1 = [Sample|Samples],
  {Samples2, _} = lists:splitwith(fun(X) -> X > Now - WindowTime end, Samples1),
  Window#window{samples = Samples2}.

-spec(count_ticks(window()) -> non_neg_integer()).
count_ticks(_Window = #window{window_time = WindowTime, samples = Samples}) ->
  Now = erlang:monotonic_time(milli_seconds),
  {Samples1, _} = lists:splitwith(fun(X) -> X > Now - WindowTime end, Samples),
  length(Samples1).

-spec(compare_vclocks(V1 :: riak_dt_vclock:vclock(), V2 :: riak_dt_vclock:vclock()) -> gt | lt | equal | concurrent).
compare_vclocks(V1, V2) ->
  %% V1 dominates V2
  DominatesGT = riak_dt_vclock:dominates(V1, V2),
  DominatesLT = riak_dt_vclock:dominates(V2, V1),
  Equal = riak_dt_vclock:equal(V1, V2),
  case {DominatesGT, DominatesLT, Equal} of
    {true, _, _} ->
      gt;
    {_, true, _} ->
      lt;
    {_, _, true} ->
      equal;
    {_, _, _} ->
      concurrent
  end.

-spec(subtract(List1, List2) -> Set when
  List1 :: [Type, ...],
  List2 :: [Type, ...],
  Set :: ordsets:ordset(Type),
  Type :: term()).

%% @doc
%% This is equivalent to lists:subtract
%% This comes from a bunch of empirical benchmarking
%% That for small sets, it's cheaper to do ordsets:from_list
%% and use that subtraction method
%% It returns a sorted set back
%% @end
subtract(List1, List2) ->
  List1Set = ordsets:from_list(List1),
  List2Set = ordsets:from_list(List2),
  ordsets:subtract(List1Set, List2Set).

%% Borrowed from: https://github.com/basho/riak_ensemble/blob/develop/src/riak_ensemble_util.erl
-spec replace_file(file:filename(), iodata()) -> ok | {error, term()}.
replace_file(FN, Data) ->
  TmpFN = FN ++ ".tmp",
  {ok, FH} = file:open(TmpFN, [write, raw]),
  try
    ok = file:write(FH, Data),
    ok = file:sync(FH),
    ok = file:close(FH),
    ok = file:rename(TmpFN, FN),
    {ok, Contents} = read_file(FN),
    true = (Contents == iolist_to_binary(Data)),
    ok
  catch _:Err ->
    {error, Err}
  end.

%%===================================================================

%% @doc Similar to {@link file:read_file/1} but uses raw file I/O
-spec read_file(file:filename()) -> {ok, binary()} | {error, _}.
read_file(FName) ->
  case file:open(FName, [read, raw, binary]) of
    {ok, FD} ->
      Result = read_file(FD, []),
      ok = file:close(FD),
      case Result of
        {ok, IOList} ->
          {ok, iolist_to_binary(IOList)};
        {error, _} = Err ->
          Err
      end;
    {error, _} = Err ->
      Err
  end.

-spec read_file(file:fd(), [binary()]) -> {ok, [binary()]} | {error, _}.
read_file(FD, Acc) ->
  case file:read(FD, 4096) of
    {ok, Data} ->
      read_file(FD, [Data | Acc]);
    eof ->
      {ok, lists:reverse(Acc)};
    {error, _} = Err ->
      Err
  end.
