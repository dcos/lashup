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
-export([start_link/1, start_link/2, init/1]).

-record(state, {
  match_spec :: ets:match_spec(),
  match_spec_comp :: ets:comp_match_spec(),
  pid :: pid(),
  ref :: reference(),
  vclocks = orddict:new() :: orddict:orddict()
}).

-include("lashup_kv.hrl").

start_link(MatchSpec) ->
  start_link(node(), MatchSpec).

%% The matchspec must be in the format fun({Key}) when GuardSpecs -> true end
start_link(Node, MatchSpec) ->
  Ref = make_ref(),
  MatchSpecCompiled = ets:match_spec_compile(MatchSpec),
  State = #state{pid = self(), match_spec_comp = MatchSpecCompiled, ref = Ref, match_spec = MatchSpec},
  Pid = spawn_link(Node, ?MODULE, init, [State]),
  true = is_pid(Pid),
  {ok, Ref}.

init(State) ->
  ok = mnesia:wait_for_tables([kv], 5000),
  mnesia:subscribe({table, kv, detailed}),
  State1 = dump_events(State),
  loop(State1).

loop(State) ->
  receive
    {mnesia_table_event, {write, _Table = kv, NewRecord, OldRecords, _ActivityId}} ->
      State1 = maybe_process_event(NewRecord, OldRecords, State),
      loop(State1);
    Any ->
      lager:warning("Got something unexpected: ~p", [Any]),
      loop(State)
  end.


%   Event = #{key => Key, map => Map, vclock => VClock, value => Value, ref => Reference},

maybe_process_event(NewRecord = #kv{key = Key}, OldRecords, State = #state{match_spec_comp = MatchSpec}) ->
  case ets:match_spec_run([{Key}], MatchSpec) of
    [true] ->
      maybe_process_event2(NewRecord, OldRecords, State);
    [] ->
      State
  end.

maybe_process_event2(NewRecord = #kv{key = Key}, OldRecords, State = #state{vclocks = VClocks}) ->
  case orddict:find(Key, VClocks) of
    error ->
      send_event(NewRecord, OldRecords, State),
      #kv{vclock = ForeignVClock} = NewRecord,
      update_state(Key, ForeignVClock, State);
    {ok, VClock} ->
      maybe_process_event3(NewRecord, OldRecords, VClock, State)
  end.

maybe_process_event3(NewRecord = #kv{vclock = ForeignVClock, key = Key}, OldRecords, LocalVClock, State) ->
  case riak_dt_vclock:dominates(ForeignVClock, LocalVClock) of
    false ->
      State;
    true ->
      send_event(NewRecord, OldRecords, State),
      update_state(Key, ForeignVClock, State)
  end.

update_state(Key, VClock, State = #state{vclocks = VClocks}) ->
  VClocks1 = orddict:store(Key, VClock, VClocks),
  State#state{vclocks = VClocks1}.

%% Rewrite the ref and send the event
send_event(_NewRecord = #kv{key = Key, map = Map}, [], #state{ref = Ref, pid = Pid}) ->
  Value = riak_dt_map:value(Map),
  Event = #{type => ingest_new, key => Key, ref => Ref, value => Value},
  Pid ! {lashup_kv_events, Event};
send_event(_NewRecord = #kv{key = Key, map = Map} = _NewRecords,
  [#kv{map = OldMap}] = _OldRecords, #state{ref = Ref, pid = Pid}) ->
  OldValue = riak_dt_map:value(OldMap),
  Value = riak_dt_map:value(Map),
  Event = #{type => ingest_update, key => Key, ref => Ref, value => Value, old_value => OldValue},
  Pid ! {lashup_kv_events, Event}.

dump_events(State = #state{match_spec = MatchSpec}) ->
  RewrittenMatchspec = rewrite_matchspec(MatchSpec),
  Records = mnesia:dirty_select(kv, RewrittenMatchspec),

  dump_events(Records, State),
  VClocks = ordsets:from_list([{Key, VClock} || #kv{key = Key, vclock = VClock} <- Records]),
  State#state{vclocks = VClocks}.

dump_events(Records, State) ->
  [send_event(Record, [], State) || Record <- Records].


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

