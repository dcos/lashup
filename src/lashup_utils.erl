%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Jan 2016 8:59 PM
%%%-------------------------------------------------------------------
-module(lashup_utils).
-author("sdhillon").

%% API
-export([seed/0, shuffle_list/2, new_window/1, add_tick/1, count_ticks/1, compare_vclocks/2,
  get_dcos_ip/0, erlang_nodes/1, maybe_poll_for_master_nodes/0, nodekey/2, subtract/2,
  wakeup_loop/2, wakeup_loop/1, linear_ramp_up/2]).

-record(window, {
  samples = [] :: list(integer()),
  window_time = 0 :: non_neg_integer()}).

-type window() :: #window{}.

-export_type([window/0]).

-spec(seed() -> random:ran()).
seed() ->
  {erlang:phash2([node()]),
  erlang:monotonic_time(),
  erlang:unique_integer()}.

-spec shuffle_list(List, Seed :: random:ran()) -> List1 when
  List :: [T, ...],
  List1 :: [T, ...],
  T :: term().
shuffle_list(List, FixedSeed) ->
  {_, PrefixedList} =
    lists:foldl(fun(X, {SeedState, Acc}) ->
      {N, SeedState1} = random:uniform_s(1000000, SeedState),
      {SeedState1, [{N, X} | Acc]}
                end,
      {FixedSeed, []},
      List),
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
  if
    DominatesGT ->
      gt;
    DominatesLT ->
      lt;
    Equal ->
      equal;
    true ->
      concurrent
  end.

-spec(get_dcos_ip() -> false | inet:ip4_address()).
get_dcos_ip() ->
  case inet:parse_ipv4_address(os:cmd("/opt/mesosphere/bin/detect_ip")) of
    {ok, IP} ->
      IP;
    {error, einval} ->
      false
  end.

-spec(maybe_poll_for_master_nodes() -> [node()]).
maybe_poll_for_master_nodes() ->
  IPs = inet_res:lookup("master.mesos", in, a, [], 1000),
  Nodes = [erlang_nodes(IP) || IP <- IPs],
  NaiveNodes = [lists:flatten(io_lib:format("minuteman@~s", [inet:ntoa(IP)])) || IP <- IPs],
  NaiveNodesAtoms = [list_to_atom(X) || X <- NaiveNodes],
  FlattenedNodes = lists:flatten(Nodes) ++ NaiveNodesAtoms,
  FlattenedNodesSet = ordsets:from_list(FlattenedNodes),
  FlattenedNodesSet.


-spec(erlang_nodes(IP :: inet:ip4_address()) -> [node()]).
erlang_nodes(IP) ->
  case net_adm:names(IP) of
    {error, _} ->
      [];
    {ok, NamePorts} ->
      IPPorts = [{IP, Port} || {_Name, Port} <- NamePorts],
      lists:foldl(fun ip_port_to_nodename/2, [], IPPorts)
  end.

%% Borrowed the bootstrap of the disterl protocol :)

ip_port_to_nodename({IP, Port}, Acc) ->
  case gen_tcp:connect(IP, Port, [binary, {packet, 2}, {active, false}], 500) of
    {error, _Reason} ->
      Acc;
    {ok, Socket} ->
      try_connect_ip_port_to_nodename(Socket, Acc)
  end.

try_connect_ip_port_to_nodename(Socket, Acc) ->
  %% The 3rd field, flags
  %% is set statically
  %% it doesn't matter too much
  Random = random:uniform(100000000),
  Nodename = iolist_to_binary(io_lib:format("r-~p@254.253.252.251", [Random])),
  NameAsk = <<"n", 00, 05, 16#37ffd:32, Nodename/binary>>,
  case gen_tcp:send(Socket, NameAsk) of
    ok ->
      Acc2 = wait_for_status(Socket, Acc),
      gen_tcp:close(Socket),
      Acc2;
    _ ->
      gen_tcp:close(Socket),
      Acc
  end.

wait_for_status(Socket, Acc) ->
  case gen_tcp:recv(Socket, 0, 1000) of
    {ok, <<"sok">>} ->
      Status = <<"sok">>,
      case gen_tcp:send(Socket, Status) of
        ok ->
          wait_for_name(Socket, Acc);
        _ ->
          Acc
      end;
    _ ->
      Acc
  end.

wait_for_name(Socket, Acc) ->
  case gen_tcp:recv(Socket, 0, 1000) of
    {ok, <<"n", _Version:16, _Flags:32, _Handshake:32, Nodename/binary>>} ->
      [binary_to_atom(Nodename, latin1)|Acc];
    _ ->
      Acc
  end.

-spec(nodekey(Node :: node(), Seed :: term()) -> {integer(), Node :: node()}).
nodekey(Node, Seed) ->
  Hash = erlang:phash2({Node, Seed}),
  {Hash, Node}.

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

%% @doc Sends the message every Time to 2*Time milliseconds
%%
wakeup_loop(Message, TimeResolver) ->
  spawn_link(?MODULE, wakeup_loop, [{0, Message, TimeResolver, self()}]).

%% @private Wakeup main loop
wakeup_loop(State = {0, _, _, _}) ->
  random:seed(seed()),
  State1 = setelement(1, State, 1),
  wakeup_loop(State1);

wakeup_loop(State = {Count, Message, TimeResolver, Pid}) when is_function(TimeResolver, 0) ->
  jitter_sleep(TimeResolver()),
  Pid ! Message,
  wakeup_loop(setelement(1, State, Count + 1));
wakeup_loop(State = {Count, Message, TimeResolver, Pid}) when is_function(TimeResolver, 1) ->
  jitter_sleep(TimeResolver(Count)),
  Pid ! Message,
  wakeup_loop(setelement(1, State, Count + 1));
wakeup_loop(State = {Count, Message, Time, Pid}) when is_integer(Time) ->
  jitter_sleep(Time),
  Pid ! Message,
  wakeup_loop(setelement(1, State, Count + 1)).

jitter_sleep(Time) ->
  Multiplier = 1 + random:uniform(),
  Sleep = trunc(Time * Multiplier),
  timer:sleep(Sleep).

linear_ramp_up(TimerResolver, RampupPeriod) when is_integer(TimerResolver) ->
  linear_ramp_up(fun() -> TimerResolver end, RampupPeriod);
linear_ramp_up(TimerResolver, RampupPeriod) when is_function(TimerResolver, 0) ->
  fun(Count) ->
    (Count / RampupPeriod) * TimerResolver()
  end;
linear_ramp_up(TimerResolver, RampupPeriod) when is_function(TimerResolver, 1) ->
  fun(Count) ->
    (Count / RampupPeriod) * TimerResolver(Count)
  end.



