%%% @doc A nice little library to setup dynamic timers that are

-module(lashup_timers).
-author("sdhillon").

-ifdef(TEST).
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
  wakeup_loop/2,
  loop_calculate_time/1,
  linear_ramp_up/2,
  wait/2,
  jitter_uniform/2,
  jitter_uniform/1,
  time_remaining/1,
  cancel/1,
  limit_count/2,
  reset/1,
  skip/1
]).

-export_type([lashup_timer/0, timer_resolver/0]).

-record(wakeup_loop, {
  count,
  message,
  resolver,
  pid,
  ref
}).
-record(report_time, {
  ref,
  from
}).
-record(report_time_reply, {
  ref,
  ms
}).

-record(lashup_timer, {
  pid :: pid(),
  ref :: reference()
}).
-type lashup_timer() :: #lashup_timer{}.

-type timer_resolver() :: integer() |
                          fun (() -> integer()) |
                          fun ((Count :: pos_integer()) -> integer()).


reset(#lashup_timer{pid = Pid}) ->
  reset ! Pid.

skip(#lashup_timer{pid = Pid}) ->
  skip ! Pid.

cancel(#lashup_timer{pid = Pid}) ->
  Pid ! cancel.

time_remaining(#lashup_timer{pid = Pid}) ->
  MonitorRef = monitor(process, Pid),
  Ref = make_ref(),
  Pid ! #report_time{ref = Ref, from = self()},
  receive
    #report_time_reply{ms = MS, ref = Ref} ->
      {ok, MS};
    {'DOWN', MonitorRef, _, _, Info} ->
      {error, Info}
  end.

%% @doc Dynamic Timers!

-spec(wakeup_loop(Message :: term(), TimerResolver :: timer_resolver()) -> lashup_timer()).
wakeup_loop(Message, TimeResolver) ->
  Ref = make_ref(),
  State = #wakeup_loop{count = 1, message = Message, resolver = TimeResolver, pid = self(), ref = Ref},
  Pid = spawn_link(?MODULE, loop_calculate_time, [State]),
  #lashup_timer{pid = Pid, ref = Ref}.

loop_calculate_time(State = #wakeup_loop{count = Count, resolver = TimeResolver}) ->
  SleepTime = (to_function_with_arity(1, TimeResolver))(Count),
  WhenToFire = erlang:monotonic_time(milli_seconds) + SleepTime,
  loop_sleep(WhenToFire, State).

loop_sleep(WhenToFire, State = #wakeup_loop{pid = Pid, count = Count}) ->
  MSToFireIn = round(WhenToFire - erlang:monotonic_time(milli_seconds)),
  TimeRemaining = max(0, MSToFireIn),
  receive
    reset ->
      loop_calculate_time(State);
    skip ->
      loop_calculate_time(State#wakeup_loop{count = Count + 1});
    cancel ->
      unlink(Pid);
    #report_time{} = ReportTime ->
      report_time(TimeRemaining, ReportTime),
      loop_sleep(WhenToFire, State)
  after TimeRemaining ->
    fire_event_and_continue(State)
  end.

fire_event_and_continue(State = #wakeup_loop{pid = Pid, message = Message, count = Count}) ->
  Pid ! Message,
  loop_calculate_time(State#wakeup_loop{count = Count + 1}).

report_time(TimeRemainingMS, #report_time{from = From, ref = Ref}) ->
  From ! #report_time_reply{ref = Ref, ms = TimeRemainingMS}.

%% @doc limit the number of times this loops
%% Anything smaller than 0 doesn't really really make sense
%%% It should be put inside the wait function
limit_count(MaxCount, TimerResolver) ->
  fun
    (Count) when Count > MaxCount ->
      self() ! cancel,
      (to_function_with_arity(1, TimerResolver))(Count);
    (Count) ->
      (to_function_with_arity(1, TimerResolver))(Count)
  end.

% @doc It makes the clock go faster until RampupPeriods counts have gone by
linear_ramp_up(RampupPeriod, TimerResolver) ->
  fun(Count) ->
    (Count / RampupPeriod) * (to_function_with_arity(1, TimerResolver))(Count)
  end.

%% @doc introduces a wait before the first tick. It must be the outtermost function to work correctly
%% It does this by 'stealing' the first tick, but it corrects the tick count for the inner functions
wait(WaitTime, TimerResolver) when WaitTime > 0 ->
  fun
    (1) ->
      WaitTime;
    (Count) ->
      (to_function_with_arity(1, TimerResolver))(Count - 1)
  end.

% @doc When you add the jitter modifier, it makes it so that the clock last at least as long as the inner resolver
% but up to Factor times the amount
% (example, factor of 1, with a 500 ms timer could make it sleep anywhere between 500-1000ms)
% 0 -> 500ms
% 1 -> 500 - 1000ms
% 2 -> 500 - 1500ms
% Uses the exs1024 algorithm
jitter_uniform(Factor, TimerResolver) when Factor >= 0 ->
  fun(Count) ->
    case Count of
      1 ->
        rand:seed(exsplus);
      _ ->
        ok
    end,
    Multiplier = 1 + (Factor * rand:uniform()),
    Multiplier * (to_function_with_arity(1, TimerResolver))(Count)
  end.

%% @doc Like jitter_uniform(2, TimerResolver)
jitter_uniform(TimerResolver) ->
  jitter_uniform(1, TimerResolver).

%% @private
%% Wraps a function in another function to get the desired arity
%% It just drops the arguments
%% There is probably a better way to do this, but alas
to_function_with_arity(Arity, Time)  when is_integer(Time) ->
  to_function_with_arity(Arity, fun() -> Time end);
to_function_with_arity(Arity, Function) when is_function(Function, Arity) ->
  Function;
%% This is for configuration functions and the like
to_function_with_arity(1, Function) when is_function(Function, 0) ->
  fun(_) ->
    Function()
  end.

-ifdef(TEST).

proper_test() ->
  true = proper:quickcheck(resolvers_work(), [{numtests, 1000}]).

resolvers() ->
  %% This generates a symbolic command sequence
  non_empty(list(resolver())).

resolver_and_initial_value() ->
  {pos_integer(), pos_integer(), resolvers()}.

resolver() ->
  oneof([
    {limit_count, [non_neg_integer()]},
    {jitter_uniform, []},
    {linear_ramp_up, [pos_integer()]},
    {wait, [pos_integer()]}
  ]).

evaluate([], Last) ->
  Last;
evaluate([{F, A}|Resolvers], Value) ->

  New = apply(?MODULE, F, A ++ [Value]),
  evaluate(Resolvers, New).

resolvers_work() ->
  ?FORALL(Config, resolver_and_initial_value(),
    begin
      {InitialValue, Count, Resolvers} = Config,
      Result = (evaluate(Resolvers, InitialValue))(Count),
      is_number(Result) andalso Result >= 0
    end).

flush(Ref) ->
  flush(0, Ref).

flush(Count, Ref) ->
  receive
    Ref ->
      flush(Count + 1, Ref)
    after 1000 ->
    Count
  end.

report_time_test() ->
  Ref = make_ref(),
  Timer = lashup_timers:wakeup_loop(Ref, 10000),
  {ok, TimeLeft} = time_remaining(Timer),
  ?assert(TimeLeft =< 10000 andalso TimeLeft >= 0).

cancel_timer_test() ->
  Ref = make_ref(),
  Timer = lashup_timers:wakeup_loop(Ref, 100),
  cancel(Timer),
  flush(Ref),
  ?assertEqual(0, flush(Ref)).

limit_test() ->
  Ref = make_ref(),
    lashup_timers:wakeup_loop(Ref,
      lashup_timers:limit_count(5,
        10)),
  ?assertEqual(5, flush(Ref)).

-endif.
