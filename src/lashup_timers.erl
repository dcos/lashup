%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%% A nice little library to setup dynamic timers that are
%%% @end
%%% Created : 09. Feb 2016 7:15 AM
%%%-------------------------------------------------------------------
-module(lashup_timers).
-author("sdhillon").

-export([wakeup_loop/2, wakeup_loop/1, linear_ramp_up/2, wait/2, jitter_uniform/2, jitter_uniform/1]).
-record(state, {count, message, resolver, pid}).

%% @doc Sends the message every Time to 2*Time milliseconds
%%
wakeup_loop(Message, TimeResolver) ->
  State = #state{count = 1, message = Message, resolver = TimeResolver, pid = self()},
  spawn_link(?MODULE, wakeup_loop, [State]).

wakeup_loop(State = #state{count = Count, resolver = TimeResolver, pid = Pid, message = Message}) ->
  SleepTime = (to_function_with_arity(1, TimeResolver))(Count),
  sleep(SleepTime),
  Pid ! Message,
  wakeup_loop(State#state{count = Count + 1}).

sleep(Time) ->
  timer:sleep(round(Time)).

% @doc It makes the clock go faster until RampupPeriods counts have gone by

linear_ramp_up(RampupPeriod, TimerResolver) ->
  fun(Count) ->
    (Count / RampupPeriod) * (to_function_with_arity(1, TimerResolver))(Count)
  end.

%% @doc introduces a wait before the first tick. It must be the outtermost function to work correctly
%% It does this by 'stealing' the first tick, but it corrects the tick count for the inner functions
wait(WaitTime, TimerResolver)  ->
  fun
    (1) ->
      WaitTime;
    (Count) ->
      (to_function_with_arity(1, TimerResolver))(Count - 1)
  end.

% @doc When you add the jitter modifier, it makes it so that the clock last at least as long as the inner resolver
% but up to Factor times the amount
% (example, factor of 2, with a 500 ms timer could make it sleep anywhere between 500-1000ms)
% Factor must be greater than 1 (no subsleeps)
% Uses the exs1024 algorithm
jitter_uniform(Factor, TimerResolver) when Factor > 1 ->
  fun(Count) ->
    case Count of
      1 ->
        rand:seed(exs1024);
      _ ->
        ok
    end,
    Multiplier = (Factor - 1) * rand:uniform(),
    Multiplier * (to_function_with_arity(1, TimerResolver))(Count)
  end.

%% @doc Like jitter_uniform(2, TimerResolver)
jitter_uniform(TimerResolver) ->
  jitter_uniform(2, TimerResolver).

%% @private
%% Wraps a function in another function to get the desired arity
%% It just drops the arguments
%% There is probably a better way to do this, but alas
to_function_with_arity(Arity, Time)  when is_integer(Time) ->
  to_function_with_arity(Arity, fun() -> Time end);
to_function_with_arity(Arity, Function) when is_function(Function, Arity) ->
  Function;
to_function_with_arity(1, Function) when is_function(Function, 0) ->
  fun(_) ->
    Function()
  end.