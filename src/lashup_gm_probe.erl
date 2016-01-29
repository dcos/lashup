%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Jan 2016 9:27 PM
%%%-------------------------------------------------------------------
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

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {digraph :: digraph:digraph()}).


-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  random:seed(lashup_utils:seed()),
  {ok, Digraph} = lashup_gm:get_digraph(),
  State = #state{digraph = Digraph},
  schedule_next_probe(),
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
  State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_info(do_probe, State) ->
  do_probe(State),
  {noreply, State};
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
  State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
  Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
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
  RandFloat = random:uniform(),
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

-spec(do_probe(#state{}) -> ok).
do_probe(_State = #state{digraph = Digraph}) ->
  StrongComponents = digraph_utils:strong_components(Digraph),
  Node = node(),
  Pred = fun(Component) -> lists:member(Node, Component) end,
  {[ReachableNodes], OtherComponents} = lists:partition(Pred, StrongComponents),
  OtherComponents1 = lists:flatten(OtherComponents),
  case OtherComponents1 of
    [] ->
      schedule_next_probe(),
      ok;
    _ ->
      Idx = random:uniform(length(OtherComponents1)),
      OtherNode = lists:nth(Idx, OtherComponents1),
      lashup_hyparview_membership:recommend_neighbor(OtherNode),
      ProbeTime = determine_next_probe(ReachableNodes, OtherComponents1),
      schedule_next_probe(ProbeTime),
      ok
  end.






