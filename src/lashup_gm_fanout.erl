-module(lashup_gm_fanout).
-author("sdhillon").

-include_lib("stdlib/include/ms_transform.hrl").
-include("lashup.hrl").

%% Lashup GM fanout is the global membership fanout system
%% It is composed of three components
%% 1. The lashup_gm process that's generating the events
%% 2. Itself
%% 3. The lashup_gm process that's receiving the events

%% The actual fan-out is handled by lashup_gm

%% API
-export([
    start_monitor/1,
    init/1
]).

-record(state, {
    parent,
    receiver,
    receiver_mon,
    parent_mon,
    node
}).


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
      gen_server:cast({lashup_gm, Node}, {sync, self()}),
      State1 = State#state{receiver_mon = ReceiverMon, parent_mon = ParentMon, parent = Parent},
      event_loop(State1);
    Else ->
      lager:debug("Lashup GM Fanout unable to subscribe: ~p", [Else]),
      exit({unable_to_subscribe, Else})
  end.

event_loop(State) ->
  State1 =
  receive
    #{type := aae_keys} = AAEKeys ->
      aae_keys(AAEKeys, State);
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

%% AAE Keys is the initial sync process
%% We have to send out full list of [{Node, VClock}] list to this pid
%% In return it filters the one that it has newer vclocks for
%% And sends them back
%% TODO: Monitor / link against the sync worker
aae_keys(#{pid := Pid}, State) ->
  NodeClocks = node_clocks(),
  [Pid ! #{type => node_clock, node_clock => NodeClock} || NodeClock <- NodeClocks],
  Pid ! #{type => node_clock_complete},
  State.

-spec(node_clocks() -> [{node(), riak_dt_vclock:vclock()}]).
node_clocks() ->
  MatchSpec = ets:fun2ms(
    fun(Member = #member2{value = Value}) ->
      {Member#member2.node, Value}
    end
  ),
  Result = ets:select(members, MatchSpec),
  NodeClocks = [{NodeName, {Epoch, Clock}} || {NodeName, #{epoch := Epoch, clock := Clock}} <- Result],
  orddict:from_list(NodeClocks).
