%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Jan 2016 10:04 PM
%%%-------------------------------------------------------------------
-module(lashup_hyparview_ping_handler).
-author("sdhillon").

-behaviour(gen_server).

%% API
-export([start_link/0,
  ping/1]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).


-define(PING_RETENTION_COUNT, 100).
%% In seconds
%% We both use this to trim samples, and nodes totally from the dict
-define(PING_RETENTION_TIME, 60).
%% This is to purge nodes that left our active view
%% It really should be bigger than the ping retention time
%% It is when we last saw them
%% Not a matter of running retention time and retention count on them
-define(PING_PURGE_INTERVAL, 900).

%% If we don't ping the node for 60 seconds, we can invalidate the history
-define(PING_CONTUINITY, 10).

-define(MAX_PING_MS, 1000).

%% This is effectively how much we expect the RTT to jump
%% 5X the highest measured RTT over the past minute, or 100 pings, whichever is smaller
-define(HEADROOM, 5).


%% Given how the failure detector is tuned today, we might do 100 pings to a given node in
%% out active view in between 10-60 seconds.

%% So, I could do something clever, where if we have an old RTT that was high
%% We could rule it out
%% But, these anomalies should automatically cut themselves out via the

%% Recorded time, and RTT are both in "native"
-type ping_record() :: {RecordedTime :: integer(), RTT :: integer()}.

-record(state, {
  pings_in_flight = orddict:new() :: orddict:orddict(Reference :: reference(), Node :: node()),
  ping_times = dict:new() :: dict:dict(Node :: node(), PingRecord :: ping_record())
}).
-type state() :: #state{}.

-type pong_message() :: map().
-type ping_message() :: map().

%%%===================================================================
%%% API
%%%===================================================================

-spec(ping(Node :: node()) -> ok).
ping(Node) ->
  gen_server:call(?SERVER, {ping, Node}),
  ok.


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
  {ok, State :: state()} | {ok, State :: state(), timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  %% The reason not to randomize this is that we'd prefer all nodes pause around the same time
  %% It creates an easier to debug situation if this call actually does kill performance
  SendIntervalMS = erlang:convert_time_unit(?PING_PURGE_INTERVAL, seconds, milli_seconds),
  timer:send_interval(SendIntervalMS, purge),
  {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
  State :: state()) ->
  {reply, Reply :: term(), NewState :: state()} |
  {reply, Reply :: term(), NewState :: state(), timeout() | hibernate} |
  {noreply, NewState :: state()} |
  {noreply, NewState :: state(), timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: state()} |
  {stop, Reason :: term(), NewState :: state()}).
handle_call({ping, Node}, _From, State) ->
  State1 = do_ping(Node, State),
  {reply, ok, State1};
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: state()) ->
  {noreply, NewState :: state()} |
  {noreply, NewState :: state(), timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: state()}).
handle_cast(PingMessage = #{message := ping}, State) ->
  handle_ping(PingMessage, State),
  {noreply, State};
handle_cast(PongMessage = #{message := pong}, State) ->
  State1 = handle_pong(PongMessage, State),
  {noreply, State1};
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
-spec(handle_info(Info :: timeout() | term(), State :: state()) ->
  {noreply, NewState :: state()} |
  {noreply, NewState :: state(), timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: state()}).
handle_info(purge, State) ->
  State1 = handle_purge(State),
  {noreply, State1};
handle_info({ping_failed, NRef}, State) ->
  State1 = handle_ping_failed(NRef, State),
  {noreply, State1};
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
  State :: state()) -> term()).
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
-spec(code_change(OldVsn :: term() | {down, term()}, State :: state(),
  Extra :: term()) ->
  {ok, NewState :: state()} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


-spec(do_ping(Node :: node(), State :: state()) -> State1 :: state()).
do_ping(Node, State) ->
  PIF = State#state.pings_in_flight,
  Now = erlang:monotonic_time(),
  Ref = make_ref(),
  {MaxEstRTT, State1} = determine_ping_time(Node, State),
  {ok, TimerRef} = timer:send_after(MaxEstRTT, {ping_failed, Ref}),
  gen_server:cast({?SERVER, Node}, #{message => ping, from => self(), now => Now, ref => Ref, timer_ref => TimerRef}),
  PIF2 = orddict:store(Ref, {MaxEstRTT, Node}, PIF),
  State1#state{pings_in_flight = PIF2}.

-spec(handle_ping_failed(Ref :: reference(), State :: state()) -> State1 :: state()).
handle_ping_failed(Ref, State = #state{ping_times = PingTimes}) ->
  PIF = State#state.pings_in_flight,
  case orddict:find(Ref, PIF) of
    {ok, {RTT, Node}} ->
      lager:info("Didn't receive Pong from Node: ~p in time: ~p", [Node, RTT]),
      lashup_hyparview_membership:ping_failed(Node),
      PIF2 = orddict:erase(Ref, PIF),
      PingTimes2 = dict:erase(Node, PingTimes),
      State#state{pings_in_flight = PIF2, ping_times = PingTimes2};
    error ->
      State
  end.

-spec(handle_ping(PingMessage :: ping_message(), State :: state()) -> ok).
handle_ping(PingMessage = #{from := From}, _State) ->
  PongMessage = PingMessage#{message => pong, receiving_node => node()},
  gen_server:cast(From, PongMessage),
  ok.

%% TODO: Keep track of RTTs somewhere

-spec(handle_pong(PongMessage :: pong_message(), State :: state()) -> State1 :: state()).
handle_pong(PongMessage = #{ref := Ref, timer_ref := TimerRef}, State) ->
  lashup_hyparview_membership:recognize_pong(PongMessage),
  PIF = State#state.pings_in_flight,
  timer:cancel(TimerRef),
  PIF2 = orddict:erase(Ref, PIF),
  State1 = record_pong(PongMessage, State),
  State1#state{pings_in_flight = PIF2}.

%% This stores the pongs and pong timings
-spec(record_pong(PongMessage :: pong_message(), State :: state()) -> State1 :: state()).
record_pong(_PongMessage = #{receiving_node := ReceivingNode, now := SendTime},
    State = #state{ping_times = PingTimes}) ->
  %% {RecordedTime :: integer(), RTT :: integer()}
  Now = erlang:monotonic_time(),
  RTT = Now - SendTime,
  RetentionTime = Now - erlang:convert_time_unit(?PING_RETENTION_TIME, seconds, native),
  %% Filters both on retention time
  %% And retention count
  %% Contuinity should be handled at ping time, I think
  UpdateFun =
    fun(RecordedTimes) ->
      RecordedTimes1 = lists:sublist(RecordedTimes, 1, ?PING_RETENTION_COUNT - 1),
      RecordedTimes2 = [Entry || Entry = {RecordedTime, _} <- RecordedTimes1, RecordedTime > RetentionTime],
      [{Now, RTT}|RecordedTimes2]
    end,
  %% We record the MAX_PING_MS (over headroom) so we can get a baseline over a minute

  BaseLine = {Now, trunc(?MAX_PING_MS / ?HEADROOM)},
  Initial = [{erlang:monotonic_time(), RTT}, BaseLine],
  PingTimes1 = dict:update(ReceivingNode, UpdateFun, Initial, PingTimes),
  State#state{ping_times = PingTimes1}.

-spec(determine_ping_time(Node :: node(), State :: state()) -> {RTT :: non_neg_integer(), State1 :: state()}).
determine_ping_time(Node, State = #state{ping_times = PingTimes})  ->
  %% If unknown then might as well return the MAX PING
  case dict:find(Node, PingTimes) of
    error ->
      {?MAX_PING_MS, State};
    {ok, PingRecords} ->
      {RTT, PingRecords1} = determine_ping_time2(PingRecords),
      PingTimes1 = dict:store(Node, PingRecords1, PingTimes),
      State1 = State#state{ping_times = PingTimes1},
      {RTT, State1}
  end.

-spec(determine_ping_time2([ping_record()]) -> {RTT :: non_neg_integer(), [ping_record()]}).
determine_ping_time2(RecordedTimes) ->
  Now = erlang:monotonic_time(),
  RetentionTime = Now - erlang:convert_time_unit(?PING_RETENTION_TIME, seconds, native),
  RecordedTimes1 = [Entry || Entry = {RecordedTime, _} <- RecordedTimes, RecordedTime > RetentionTime],
  case RecordedTimes1 of
    [] ->
      {?MAX_PING_MS, []};
    _ ->
      [InitialAcc|Rest] = RecordedTimes1,
      RecordedTimes2 = lists:foldl(fun filter_continuity_fold/2, [InitialAcc], Rest),
      RTTs = [RTT || {_, RTT} <- RecordedTimes2],
      MaxRTT = lists:max(RTTs),
      MaxRTTMS = erlang:convert_time_unit(trunc(MaxRTT), native, milli_seconds),
      MaxRTTMSBound = (1 + MaxRTTMS) * ?HEADROOM,
      MaxRTTMSBound1 = min(MaxRTTMSBound, ?MAX_PING_MS),
      {MaxRTTMSBound1, RecordedTimes2}
  end.

-spec(filter_continuity_fold(ping_record(), [ping_record()]) -> [ping_record()]).
filter_continuity_fold(Elem = {ElemRecordedTime, _}, Acc = [{LastRecordedTime, _}|_]) ->
  MaxDelta = erlang:convert_time_unit(?PING_CONTUINITY, seconds, native),
  case LastRecordedTime - ElemRecordedTime > MaxDelta of
    true ->
      Acc;
    false ->
      [Elem|Acc]
  end.

-spec(handle_purge(state()) -> state()).
handle_purge(State = #state{ping_times = PingTimes}) ->
  Now = erlang:monotonic_time(),
  LastOkay = Now -  erlang:convert_time_unit(?PING_PURGE_INTERVAL, seconds, native),
  Predicate =
    fun
      (_Key, []) ->
        false;
      (_Key, [{_RTT, Recorded}|_]) when Recorded < LastOkay ->
        false;
      (_Key, _) ->
        true
    end,
  PingTimes1 = dict:filter(Predicate, PingTimes),
  State#state{ping_times = PingTimes1}.
