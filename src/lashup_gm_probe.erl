-module(lashup_gm_probe).
-author("sdhillon").

%%--------------------------------------------------------------------
%% @doc
%% Probe loop
%% It goes node by node in the global membership table
%% and checks if we have a path to them or not
%% If it doesn't find a path, then it checks if we have a path to the next one or not
%% Up until it hits a node greater the last node it probed

%% This is really only useful for extended partitions
%% Where either side has been partitioned from the other for an extended period of time
%% and
%% API
%% @end
%%--------------------------------------------------------------------

-behaviour(gen_server).

-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
  handle_info/2, terminate/2, code_change/3]).

-record(state, {}).

-type state() :: #state{}.

-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  rand:seed(exsplus),
  State = #state{},
  schedule_next_probe(),
  {ok, State}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(do_probe, State) ->
  maybe_do_probe(State),
  {noreply, State};
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec(schedule_next_probe() -> ok).
schedule_next_probe() ->
  ProbeInterval = lashup_config:min_departition_probe_interval(),
  schedule_next_probe(ProbeInterval).

%% We should make this configurable. It's the decision of when to make the first ping
-spec(schedule_next_probe(Time :: non_neg_integer()) -> ok).
schedule_next_probe(Time) when is_integer(Time) ->
  RandFloat = rand:uniform(),
  Multipler = 1 + round(RandFloat),
  Delay = Multipler * Time,
  timer:send_after(Delay, do_probe),
  ok.

-spec(determine_next_probe(ReachableNodes :: [node()], UnreachableNode :: [node()]) -> non_neg_integer()).
determine_next_probe(ReachableNodes, UnreachableNode) ->
  %% We want to ensure that component pings the entire other component every 10 minutes?
  %% But, we don't want to do more than 5 pings / sec as an individual node
  %% That number is somewhat arbitrary, but let's start there
  Ratio = length(ReachableNodes) / (length(UnreachableNode) + 1),
  %% Ratio is how many nodes I must ping over a probe period to fulfill the requirement set forth
  %% We divide by two, because schedule_next_probe calculates from 1x the time up to 2x the time
  FullProbePeriod = lashup_config:full_probe_period() / 2,
  ProbeInterval = FullProbePeriod / Ratio,
  MinProbeInterval = lashup_config:min_departition_probe_interval(),
  Interval = max(ProbeInterval, MinProbeInterval),
  Interval1 = min(Interval, FullProbePeriod),
  trunc(Interval1).

-spec(maybe_do_probe(state()) -> ok).
maybe_do_probe(_State) ->
  case lashup_gm_route:get_tree(node(), infinity) of
    {tree, Tree} ->
      do_probe(Tree);
    false ->
      lager:warning("Lashup GM Probe unable to get LSA Tree"),
      schedule_next_probe(),
      ok
  end.

-spec(do_probe(lashup_gm_route:tree()) -> ok).
do_probe(Tree) ->
   case lashup_gm_route:unreachable_nodes(Tree) of
    [] ->
      schedule_next_probe(),
      ok;
    UnreachableNodes ->
      probe_oneof(UnreachableNodes),
      ReachableNodes = lashup_gm_route:reachable_nodes(Tree),
      ProbeTime = determine_next_probe(ReachableNodes, UnreachableNodes),
      schedule_next_probe(ProbeTime),
      ok
  end.

-spec(probe_oneof(UnreachableNodes :: [node()]) -> ok).
probe_oneof(UnreachableNodes) ->
  Idx = rand:uniform(length(UnreachableNodes)),
  OtherNode = lists:nth(Idx, UnreachableNodes),
  lashup_hyparview_membership:recommend_neighbor(OtherNode),
  ok.
