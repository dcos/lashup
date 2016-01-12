%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 17. Jan 2016 3:44 PM
%%%-------------------------------------------------------------------
-module(lashup_gm_fanout).
-author("sdhillon").

%% Lashup GM fanout is the global membership fanout system
%% It is composed of three components
%% 1. The lashup_gm process that's generating the events
%% 2. Itself
%% 3. The lashup_gm process that's receiving the events

%% The actual fan-out is handled by lashup_gm

%% API
-export([start_monitor/1, init/1]).
-record(state, {parent, receiver, receiver_mon, parent_mon, node}).

start_monitor(Node) ->
  State = #state{receiver = self(), node = Node},
  {Pid, Monitor} = spawn_monitor(?MODULE, init, [State]),
  {ok, {Pid, Monitor}}.

init(State = #state{receiver = Receiver, node = Node}) when node() == node(Receiver) ->
  %% TODO:
  %% This might result in a reconnect,
  %% But alas, until we start changing cookies to prevent connections
  %% We can't have this work well
  ReceiverMon = monitor(process, Receiver),

  %% Investigate turning on dist_auto_connect -> once
  %% And then replacing this with explicit calls
  case gen_server:call({lashup_gm, Node}, {subscribe, self()}) of
    {ok, Parent} ->
      ParentMon = monitor(process, Parent),
      %% TODO: Implement dump_events in here
      %% Just access the ets table directly
      gen_server:cast({lashup_gm, Node}, {dump_events, self()}),
      State1 = State#state{receiver_mon = ReceiverMon, parent_mon = ParentMon, parent = Parent},
      event_loop(State1);
    Else ->
      lager:debug("Lashup GM Fanout unable to subscribe: ~p", [Else]),
      exit({unable_to_subscribe, Else})
  end.

event_loop(State) ->
  State1 =
  receive
    {event, Event} ->
      forward_event(Event, State);
    {'DOWN', MonitorRef, _Type, _Object, Info} when MonitorRef == State#state.parent_mon ->
      exit({parent_down, Info});
    {'DOWN', MonitorRef, _Type, _Object, Info} when MonitorRef == State#state.receiver_mon ->
      exit({receiver_down, Info});
    Else ->
      exit({unknown_event, Else})
  end,
  event_loop(State1).

forward_event(Event, State) when is_binary(Event) ->
  forward_event(binary_to_term(Event), State);
forward_event(Event, State = #state{receiver = Receiver}) ->
  % I'm on the same node as the receiver
  gen_server:cast(Receiver, #{message => remote_event, from => State#state.node, event => Event}),
  State.