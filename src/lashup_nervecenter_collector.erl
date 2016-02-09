%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 08. Feb 2016 7:58 AM
%%%-------------------------------------------------------------------
-module(lashup_nervecenter_collector).
-author("sdhillon").

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

-record(state, {ref = erlang:error(), rolling_buffer = #{}}).
-define(TICK_SECS, 10).
-define(MC_TOPIC_NERVECENTER, nervecenter).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
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

  {ok, Ref} = lashup_hyparview_ping_events:subscribe(),
  {ok, #state{ref = Ref}}.

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
handle_info({lashup_hyparview_ping_events, _Event = #{ref := Ref, ping_data := PingData}},
    State = #state{ref = Ref, rolling_buffer = RollingBuffer}) ->
  RollingBuffer1 = maps:merge(RollingBuffer, PingData),
  {noreply, State#state{rolling_buffer = RollingBuffer1}};
handle_info(tick, State) ->
  State1 = handle_tick(State),
  {noreply, State1};
handle_info(Info, State) ->
  lager:debug("Info: ~p", [Info]),
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


reschedule_tick() ->
  TickTime = erlang:convert_time_unit(?TICK_SECS, seconds, milli_seconds),
  reschedule_tick(TickTime).

reschedule_tick(Time) ->
  RandFloat = random:uniform(),
  Multipler = 1 + round(RandFloat),
  Delay = Multipler * Time,
  timer:send_after(Delay, tick).

handle_tick(State = #state{rolling_buffer = RollingBuffer}) ->
  reschedule_tick(),
  disseminate_buffer(RollingBuffer),
  State1 = State#state{rolling_buffer = #{}},
  State1.

disseminate_buffer(RB) ->
  %% in native time units
  %% {node => [{RecordedTime :: integer(), RTT :: integer()}]}
  RB1 = maps:filter(fun filter_empty/2, RB),
  RB2 = maps:map(fun rollup/2, RB1),
  Payload = #{type => rollup, rollup => RB2},
  lashup_gm_mc:multicast(?MC_TOPIC_NERVECENTER, Payload, [loop, {fanout, 1}]).

filter_empty(_, []) -> false;
filter_empty(_, _) -> true.

rollup(_Key, Measurements) ->
  RTTs = [erlang:convert_time_unit(RTT, native, milli_seconds) || {_, RTT} <-  Measurements],
  SortedRTTs = lists:sort(RTTs),
  Length = length(RTTs),
  Median = lists:nth(round(Length/2), SortedRTTs),
  Mean = round(lists:sum(RTTs) / Length),
  #{mean => Mean, median => Median}.


