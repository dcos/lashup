-module(lashup_hyparview_ping_handler).
-author("sdhillon").
-behaviour(gen_server).

%% API
-export([
  start_link/0,
  ping/1,
  check_max_ping_ms/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
  handle_info/2, terminate/2, code_change/3]).

-record(state, {
  pings_in_flight = orddict:new() :: orddict:orddict(Reference :: reference(), Node :: node()),
  ping_times = #{} :: map()
}).
-type state() :: #state{}.

-type pong_message() :: map().
-type ping_message() :: map().


-spec(ping(node()) -> ok).
ping(Node) ->
  gen_server:call(?MODULE, {ping, Node}),
  ok.

check_max_ping_ms() ->
  %% Check if the user has manually set max ping ms, or if it's one of the settings we could have set for them
  case application:get_env(lashup, max_ping_ms) of
    Val when Val == undefined orelse Val == 10000 orelse Val == 30000->
      check_max_ping_ms2();
    _ ->
      ok
  end.

check_max_ping_ms2() ->
  case lashup_gm:gm() of
    Members when length(Members) > 1000 ->
      application:set_env(lashup, ping_log_base, 1.0009),
      application:set_env(lashup, max_ping_ms, 30000);
    Members when length(Members) > 500 ->
      application:set_env(lashup, ping_log_base, 1.00034),
      application:set_env(lashup, max_ping_ms, 10000);
    _ ->
      ok
  end.

-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  process_flag(priority, high),
  ok = net_kernel:monitor_nodes(true),
  %% The reason not to randomize this is that we'd prefer all nodes pause around the same time
  %% It creates an easier to debug situation if this call actually does kill performance
  timer:apply_interval(10000, ?MODULE, check_max_ping_ms, []),
  {ok, #state{}}.

handle_call({ping, Node}, _From, State) ->
  State1 = do_ping(Node, State),
  {reply, ok, State1};
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(PingMessage = #{message := ping}, State) ->
  handle_ping(PingMessage, State),
  {noreply, State};
handle_info(PongMessage = #{message := pong}, State) ->
  State1 = handle_pong(PongMessage, State),
  {noreply, State1};
handle_info({nodedown, NodeName}, State0 = #state{ping_times = PingTimes0}) ->
  PingTimes1 = maps:remove(NodeName, PingTimes0),
  State1 = State0#state{ping_times = PingTimes1},
  {noreply, State1};
handle_info({ping_failed, NRef}, State) ->
  State1 = handle_ping_failed(NRef, State),
  {noreply, State1};
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec(do_ping(node(), state()) -> state()).
do_ping(Node, State0 = #state{pings_in_flight = PIF, ping_times = PingTimes}) ->
  Now = erlang:monotonic_time(milli_seconds),
  Ref = make_ref(),
  MaxEstRTT = determine_ping_time(Node, State0),
  {ok, TimerRef} = timer:send_after(MaxEstRTT, {ping_failed, Ref}),
  Message = #{message => ping, from => self(), now => Now, ref => Ref, timer_ref => TimerRef},
  case erlang:send({?MODULE, Node}, Message, [noconnect, nosuspend]) of
    ok ->
      PIF2 = orddict:store(Ref, {MaxEstRTT, Node}, PIF),
      State0#state{pings_in_flight = PIF2};
    %% Treat ping as failed
    _ ->
      lager:info("Ping to node ~p failed, because erlang:send failed", [Node]),
      timer:cancel(TimerRef),
      lashup_hyparview_membership:ping_failed(Node),
      PingTimes2 = maps:remove(Node, PingTimes),
      State0#state{ping_times = PingTimes2}
  end.

-spec(handle_ping_failed(reference(), state()) -> state()).
handle_ping_failed(Ref, State = #state{ping_times = PingTimes, pings_in_flight = PIF}) ->
  case orddict:find(Ref, PIF) of
    {ok, {RTT, Node}} ->
      lager:info("Didn't receive Pong from Node: ~p in time: ~p", [Node, RTT]),
      lashup_hyparview_membership:ping_failed(Node),
      PIF2 = orddict:erase(Ref, PIF),
      PingTimes2 = maps:remove(Node, PingTimes),
      State#state{pings_in_flight = PIF2, ping_times = PingTimes2};
    error ->
      State
  end.

-spec(handle_ping(ping_message(), state()) -> ok).
handle_ping(PingMessage = #{from := From}, _State) ->
  PongMessage = PingMessage#{message => pong, receiving_node => node()},
  erlang:send(From, PongMessage, [noconnect, nosuspend]),
  ok.

-spec(handle_pong(pong_message(), state()) -> state()).
handle_pong(PongMessage = #{ref := Ref, timer_ref := TimerRef}, State0 = #state{pings_in_flight = PIF0}) ->
  lashup_hyparview_membership:recognize_pong(PongMessage),
  timer:cancel(TimerRef),
  PIF1 = orddict:erase(Ref, PIF0),
  State1 = record_pong(PongMessage, State0),
  State1#state{pings_in_flight = PIF1}.

%% This stores the pongs and pong timings
-spec(record_pong(pong_message(), state()) -> state()).
record_pong(_PongMessage = #{receiving_node := ReceivingNode, now := SendTime},
    State0 = #state{ping_times = PingTimes}) ->
  %% {RecordedTime :: integer(), RTT :: integer()}
  Now = erlang:monotonic_time(milli_seconds),
  LastRTT = Now - SendTime,
  PingTimes1 = PingTimes#{ReceivingNode => LastRTT},
  State0#state{ping_times = PingTimes1}.

%% RTT is in milliseconds
-spec(determine_ping_time(node(), state()) -> RTT :: non_neg_integer()).
determine_ping_time(Node, #state{ping_times = PingTimes})  ->
  %% If unknown then might as well return the MAX PING
  case maps:find(Node, PingTimes) of
    error ->
      lashup_config:max_ping_ms();
    {ok, LastRTT} ->
      %% 2 MS is the noise floor
      MinPingMs = lashup_config:min_ping_ms(),
      RTT = lists:max([MinPingMs, LastRTT]),
      trunc(math:log(RTT) / math:log(lashup_config:ping_log_base()))
  end.
