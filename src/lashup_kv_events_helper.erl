%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc Subscribes to lashup_kv events, filters them against a matchspec, and checks a vclock
%%%
%%% @end
%%% Created : 12. Feb 2016 8:54 PM
%%%-------------------------------------------------------------------
-module(lashup_kv_events_helper).
-author("sdhillon").

%% API
-export([start_link/1, init/1]).

-record(state, {
  match_spec :: ets:match_spec(),
  match_spec_comp :: ets:comp_match_spec(),
  pid :: pid(),
  ref :: reference(),
  event_ref :: reference(),
  vclocks = orddict:new() :: orddict:orddict()
}).

-include("lashup_kv.hrl").

%% The matchspec must be in the format fun({Key}) when GuardSpecs -> true end
start_link(MatchSpec) ->
  Ref = make_ref(),
  MatchSpecCompiled = ets:match_spec_compile(MatchSpec),
  State = #state{pid = self(), match_spec_comp = MatchSpecCompiled, ref = Ref, match_spec = MatchSpec},
  spawn_link(?MODULE, init, [State]),
  {ok, Ref}.

init(State) ->
  {ok, EventRef} = lashup_kv_events:subscribe(),
  State1 = State#state{event_ref = EventRef},
  State2 = dump_events(State1),
  loop(State2).

loop(State = #state{event_ref = EventRef}) ->
  receive
    Event = {lashup_kv_events, #{ref := EventRef}} ->
      State1 = maybe_process_event(Event, State),
      loop(State1)
  end.


%   Event = #{key => Key, map => Map, vclock => VClock, value => Value, ref => Reference},

maybe_process_event(Event = {_, #{key := Key}}, State = #state{match_spec_comp = MatchSpec}) ->
  case ets:match_spec_run([{Key}], MatchSpec) of
    [true] ->
      maybe_process_event2(Key, Event, State);
    [] ->
      State
  end.

maybe_process_event2(Key, Event, State = #state{vclocks = VClocks}) ->
  case orddict:find(Key, VClocks) of
    error ->
      send_event(Event, State),
      {_, #{vclock := ForeignVClock}} = Event,
      update_state(Key, ForeignVClock, State);
    {ok, VClock} ->
      maybe_process_event3(Event, Key, VClock, State)
  end.

maybe_process_event3(Event = {_, #{vclock := ForeignVClock}}, Key, LocalVClock, State) ->
  case vclock:dominates(ForeignVClock, LocalVClock) of
    false ->
      State;
    true ->
      send_event(Event, State),
      update_state(Key, ForeignVClock, State)
  end.

update_state(Key, VClock, State = #state{vclocks = VClocks}) ->
  VClocks1 = orddict:store(Key, VClock, VClocks),
  State#state{vclocks = VClocks1}.

%% Rewrite the ref and send the event
send_event({lashup_kv_events, Payload}, #state{ref = Ref, pid = Pid}) ->
  Payload1 = Payload#{ref := Ref},
  Pid ! {lashup_kv_events, Payload1}.


dump_events(State = #state{match_spec = MatchSpec}) ->
  RewrittenMatchspec = rewrite_matchspec(MatchSpec),
  Records = ets:select(lashup_kv, RewrittenMatchspec),
  dump_events(Records, State),
  VClocks = ordsets:from_list([{Key, VClock} || #kv{key = Key, vclock = VClock} <- Records]),
  State#state{vclocks = VClocks}.

dump_events(Records, State) ->
  [do_send(Record, State) || Record <- Records].

do_send(#kv{key = Key, map = Map, vclock = VClock}, State) ->
  Value = riak_dt_map:value(Map),
  Payload = #{type => ingest_new, key => Key, map => Map, vclock => VClock, value => Value, ref => undefined},
  send_event({lashup_kv_events, Payload}, State).

rewrite_matchspec(MatchSpec) ->
  [{rewrite_head(MatchHead), MatchConditions, ['$_']} || {{MatchHead}, MatchConditions, [true]} <- MatchSpec].


rewrite_head(MatchHead) ->
  RewriteFun =
    fun
      (key) ->
        MatchHead;
      (_FieldName) ->
        '_'
    end,
  MatchHead1 = [RewriteFun(FieldName) || FieldName <- record_info(fields, kv)],
  list_to_tuple([kv | MatchHead1]).

