-module(lashup_kv).
-author("sdhillon").
-behaviour(gen_server).

-include_lib("stdlib/include/ms_transform.hrl").

%% API
-export([
  start_link/0,
  request_op/2,
  request_op/3,
  keys/1,
  value/1,
  value2/1,
  raw_value/1,
  descends/2,
  subscribe/1,
  unsubscribe/1,
  flush/2,
  first_key/0,
  next_key/1,
  read_lclock/1,
  write_lclock/2,
  init_metrics/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3,
  handle_cast/2, handle_info/2]).

-export_type([key/0, lclock/0, kv2map/0, kv2raw/0]).

-define(KV_TABLE, kv2).
-define(INIT_LCLOCK, -1).
-define(WARN_OBJECT_SIZE_MB, 60).
-define(REJECT_OBJECT_SIZE_MB, 100).
-define(MAX_MESSAGE_QUEUE_LEN, 32).
-define(KV_TOPIC, lashup_kv_20161114).

-record(kv2, {
  key = erlang:error() :: key() | '_',
  map = riak_dt_map:new() :: riak_dt_map:dt_map() | '_',
  vclock = riak_dt_vclock:fresh() :: riak_dt_vclock:vclock() | '_',
  lclock = 0 :: lclock() | '_'
}).
-type kv() :: #kv2{}.

-record(nclock, {
  key :: node(),
  lclock :: lclock()
}).
-type nclock() :: #nclock{}.

-type key() :: term().
-type lclock() :: non_neg_integer(). % logical clock
-type kv2map() :: #{key => key(),
                    value => riak_dt_map:value(),
                    old_value => riak_dt_map:value()}.
-type kv2raw() :: #{key => key(),
                    value => term(),
                    vclock => riak_dt_vclock:vclock(),
                    lclock => lclock()}.

-record(state, {
  mc_ref = erlang:error() :: reference(),
  subscribers = #{} :: #{pid() => {ets:comp_match_spec(), reference()}}
}).
-type state() :: #state{}.


-spec(request_op(Key :: key(), Op :: riak_dt_map:map_op()) ->
  {ok, riak_dt_map:value()} | {error, Reason :: term()}).
request_op(Key, Op) ->
  request_op(Key, undefined, Op).

-spec(request_op(Key :: key(), Context :: riak_dt_vclock:vclock() | undefined, Op :: riak_dt_map:map_op()) ->
  {ok, riak_dt_map:value()} | {error, Reason :: term()}).
request_op(Key, VClock, Op) ->
  Pid = whereis(?MODULE),
  Args = {op, Key, VClock, Op},
  try erlang:process_info(Pid, message_queue_len) of
    {message_queue_len, MsgQueueLen} ->
      maybe_request_op_call(Pid, MsgQueueLen, Args)
  catch error:badarg ->
    exit({noproc, {gen_server, call, [?MODULE, Args]}})
  end.

-spec(maybe_request_op_call(Pid :: pid(), MsgQueueLen :: integer(),
  {op, Key :: key(), Context :: riak_dt_vclock:vclock() | undefined, Op :: riak_dt_map:map_op()}) ->
  {ok, riak_dt_map:value()} | {error, Reason :: term()}).
maybe_request_op_call(Pid, MsgQueueLen, Args) ->
  prometheus_gauge:set(lashup, kv_message_queue_length, [], MsgQueueLen),
  MaxMsgQueueLen = max_message_queue_len(),
  case MsgQueueLen > MaxMsgQueueLen of
    false ->
      prometheus_summary:observe_duration(
        lashup, kv_op_with_latency_seconds, [],
        fun () -> gen_server:call(Pid, Args, infinity) end);
    true ->
      prometheus_counter:inc(lashup, kv_message_queue_overflows_total, [], 1),
      {error, overflow}
  end.

-spec(keys(ets:match_spec()) -> [key()]).
keys(MatchSpec) ->
  op_getkeys(MatchSpec).

-spec(value(Key :: key()) -> riak_dt_map:value()).
value(Key) ->
  {_, KV} = op_getkv(Key),
  riak_dt_map:value(KV#kv2.map).

-spec(value2(Key :: key()) -> {riak_dt_map:value(), riak_dt_vclock:vclock()}).
value2(Key) ->
  {_, KV} = op_getkv(Key),
  {riak_dt_map:value(KV#kv2.map), KV#kv2.vclock}.

-spec(raw_value(key()) -> kv2raw() | false).
raw_value(Key) ->
  case op_getkv(Key) of
    {existing, #kv2{map=Map, vclock=VClock, lclock=LClock}} ->
      #{key => Key, value => Map, vclock => VClock, lclock => LClock};
    {new, _Value} ->
      false
  end.

-spec(descends(key(), riak_dt_vclock:vclock()) -> boolean()).
descends(Key, VClock) ->
  %% Check if LocalVClock is a direct descendant of the VClock
  case op_getkv(Key) of
    {existing, #kv2{vclock = LocalVClock}} ->
      riak_dt_vclock:descends(LocalVClock, VClock);
    {new, _Value} ->
      false
  end.

-spec(subscribe(ets:match_spec()) -> {ok, reference()}).
subscribe(MatchSpec) ->
  CompMatchSpec = ets:match_spec_compile(MatchSpec),
  {ok, Ref} = gen_server:call(?MODULE, {subscribe, CompMatchSpec}),
  lists:foreach(fun (Key) ->
    self() ! {lashup_kv_event, Ref, Key}
  end, keys(MatchSpec)),
  {ok, Ref}.

-spec(unsubscribe(Ref :: reference()) -> ok).
unsubscribe(Ref) ->
  ok = gen_server:call(?MODULE, {unsubscribe, Ref}),
  flush_all(Ref).

-spec(flush_all(reference()) -> ok).
flush_all(Ref) ->
  receive
    {lashup_kv_event, Ref, _Key} ->
      flush_all(Ref)
  after 0 ->
    ok
  end.

-spec(flush(Ref :: reference(), Key :: term()) -> ok).
flush(Ref, Key) ->
  receive
    {lashup_kv_event, Ref, Key} ->
      flush(Ref, Key)
  after 0 ->
    ok
  end.

-spec(first_key() -> key() | '$end_of_table').
first_key() ->
  prometheus_summary:observe_duration(
    lashup, kv_backend_read_seconds, [kv2],
    fun () -> mnesia:dirty_first(?KV_TABLE) end).

-spec(next_key(key()) -> key() | '$end_of_table').
next_key(Key) ->
  prometheus_summary:observe_duration(
    lashup, kv_backend_read_seconds, [kv2],
    fun () -> mnesia:dirty_next(?KV_TABLE, Key) end).

-spec(read_lclock(node()) -> lclock()).
read_lclock(Node) ->
  get_lclock(fun mnesia:dirty_read/2, Node).

-spec(write_lclock(node(), lclock()) -> ok | {error, term()}).
write_lclock(Node, LClock) ->
  Begin = erlang:monotonic_time(),
  Fun = fun () -> mnesia:write(#nclock{key = Node, lclock = LClock}) end,
  try mnesia:sync_transaction(Fun) of
    {atomic, _} ->
      ok;
    {aborted, Reason} ->
      lager:error("Couldn't write to nclock table because ~p", [Reason]),
      {error, Reason}
  after
    prometheus_summary:observe(
      lashup, kv_backend_write_seconds, [nclock],
      erlang:monotonic_time() - Begin)
  end.

-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  set_off_heap(),
  init_db(),
  %% Maybe read_concurrency?
  {ok, Reference} = lashup_gm_mc_events:subscribe([?KV_TOPIC]),
  {ok, #state{mc_ref = Reference}}.

handle_call({op, Key, VClock, Op}, _From, State) ->
  {Reply, State1} = handle_op(Key, Op, VClock, State),
  {reply, Reply, State1, lashup_utils:hibernate()};
handle_call({start_kv_sync_fsm, RemoteInitiatorNode, RemoteInitiatorPid}, _From, State) ->
  Result = lashup_kv_aae_sup:receive_aae(RemoteInitiatorNode, RemoteInitiatorPid),
  {reply, Result, State};
handle_call({subscribe, CompMatchSpec}, {Pid, _Tag}, State) ->
  {Ref, State0} = handle_subscribe(Pid, CompMatchSpec, State),
  {reply, {ok, Ref}, State0};
handle_call({unsubscribe, _Ref}, {Pid, _Tag}, State) ->
  State0 = handle_unsubscribe(Pid, State),
  {reply, ok, State0};
handle_call(_Request, _From, State) ->
  {reply, {error, unknown_request}, State}.

%% A maybe update from the sync FSM
handle_cast({maybe_update, Key, VClock, Map}, State0) ->
  State1 = handle_full_update(#{key => Key, vclock => VClock, map => Map}, State0),
  {noreply, State1, lashup_utils:hibernate()};
handle_cast(_Request, State) ->
  {noreply, State}.

handle_info({lashup_gm_mc_event, Event = #{ref := Ref}}, State = #state{mc_ref = Ref}) ->
  MaxMsgQueueLen = max_message_queue_len(),
  {message_queue_len, MsgQueueLen} =
    erlang:process_info(self(), message_queue_len),
  prometheus_gauge:set(lashup, kv_message_queue_length, [], MsgQueueLen),
  case MsgQueueLen > MaxMsgQueueLen of
    true ->
      lager:error("lashup_kv: message box is overflowed, ~p", [MsgQueueLen]),
      prometheus_counter:inc(lashup, kv_message_queue_overflows_total, [], 1),
      {noreply, State, lashup_utils:hibernate()};
    false ->
      State1 = handle_lashup_gm_mc_event(Event, State),
      {noreply, State1, lashup_utils:hibernate()}
  end;
handle_info({'DOWN', _MonRef, process, Pid, _Info}, State) ->
  State0 = handle_unsubscribe(Pid, State),
  {noreply, State0};
handle_info(_Info, State) ->
  {noreply, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec(max_message_queue_len() -> pos_integer()).
max_message_queue_len() ->
  application:get_env(lashup, max_message_queue_len, ?MAX_MESSAGE_QUEUE_LEN).

-spec(set_off_heap() -> on_heap | off_heap).
set_off_heap() ->
  try
    % Garbage collection with many messages placed on the heap can become
    % extremely expensive and the process can consume large amounts of memory.
    erlang:process_flag(message_queue_data, off_heap)
  catch error:badarg ->
    % off_heap options is avaliable in OTP 20.0-rc2 and later
    off_heap
  end.

%% Mostly borrowed from: https://github.com/ChicagoBoss/ChicagoBoss/wiki/Automatic-schema-initialization-for-mnesia
-spec(init_db() -> ok).
init_db() ->
  init_db([node()]).

-spec(init_db([node()]) -> ok).
init_db(Nodes) ->
  mnesia:create_schema(Nodes),
  mnesia:change_table_copy_type (schema, node(), disc_copies), % If the node was already running
  {ok, _} = application:ensure_all_started(mnesia),
  ExistingTables = mnesia:system_info(tables),
  Tables = [?KV_TABLE, nclock],
  TablesToCreate = Tables -- ExistingTables,
  Alltables = TablesToCreate ++ ExistingTables,
  lists:foreach(fun create_table/1, TablesToCreate),
  case mnesia:wait_for_tables(Alltables, 60000) of
    ok ->
      ok;
    {timeout, BadTables} ->
      lager:alert("Couldn't initialize mnesia tables: ~p", [BadTables]),
      init:stop(1);
    {error, Error} ->
      lager:alert("Couldn't initialize mnesia tables: ~p", [Error]),
      init:stop(1)
  end.

create_table(Table) ->
  {atomic, ok} =  mnesia:create_table(Table, [
    {attributes, get_record_info(Table)},
    {disc_copies, [node()]},
    {type, set}
  ]).

get_record_info(kv2) ->
  record_info(fields, kv2);
get_record_info(nclock) ->
  record_info(fields, nclock).

-spec(mk_write_fun(Key :: key(), OldVClock :: riak_dt_vclock:vclock() | undefined,
      Op :: riak_dt_map:map_op()) -> (fun())).
mk_write_fun(Key, OldVClock, Op) ->
  fun() ->
    {NewKV, NClock} =
      case safe_read(?KV_TABLE, Key) of
        [] ->
          prepare_kv(Key, riak_dt_map:new(), riak_dt_vclock:fresh(), Op);
        [#kv2{vclock = VClock}] when OldVClock =/= undefined andalso VClock =/= OldVClock ->
          mnesia:abort(concurrency_violation);
        [#kv2{vclock = VClock, map = Map}] ->
          prepare_kv(Key, Map, VClock, Op)
      end,
    case check_map(NewKV) of
      {error, Error} ->
        mnesia:abort(Error);
      ok ->
        op_write(NewKV),
        op_write(NClock)
    end,
    NewKV
  end.

-spec(safe_read(Table :: atom(), Key :: key()) -> [kv()]).
safe_read(Table, Key) ->
  prometheus_summary:observe_duration(
    lashup, kv_backend_read_seconds, [Table],
    fun () -> mnesia:read(Table, Key, write) end).

-spec(prepare_kv(Key :: key(), Map0 :: riak_dt_map:dt_map(), VClock0 :: riak_dt_vclock:vclock() | undefined,
      Op :: riak_dt_map:map_op()) -> {kv(), nclock()}).
prepare_kv(Key, Map0, VClock0, Op) ->
  Node = node(),
  VClock1 = riak_dt_vclock:increment(Node, VClock0),
  Counter = riak_dt_vclock:get_counter(Node, VClock1),
  Dot = {Node, Counter},
  Map2 =
    case
      prometheus_summary:observe_duration(
        lashup, kv_crdt_op_seconds, [],
        fun () -> riak_dt_map:update(Op, Dot, Map0) end)
    of
      {ok, Map1} -> Map1;
      {error, {precondition, {not_present, _Field}}} -> Map0
    end,
  LClock0 = get_lclock(Node),
  LClock1 = increment_lclock(LClock0),
  {#kv2{key = Key, vclock = VClock1, map = Map2, lclock = LClock1},
   #nclock{key = Node, lclock = LClock1}}.

-spec handle_op(Key :: term(), Op :: riak_dt_map:map_op(), OldVClock :: riak_dt_vclock:vclock() | undefined,
    State :: state()) -> {Reply :: term(), State1 :: state()}.
handle_op(Key, Op, OldVClock, State) ->
  Begin = erlang:monotonic_time(),
  %% We really want to make sure this persists and we don't have backwards traveling clocks
  Fun = mk_write_fun(Key, OldVClock, Op),
  try mnesia:sync_transaction(Fun) of
    {atomic, NewKV} ->
      ok = mnesia:sync_log(),
      dumped = mnesia:dump_log(),
      propagate(NewKV),
      NewValue = riak_dt_map:value(NewKV#kv2.map),
      State0 = notify_subscribers(Key, State),
      {{ok, NewValue}, State0};
    {aborted, Reason} ->
      {{error, Reason}, State}
  after
    prometheus_summary:observe(
      lashup, kv_op_seconds, [],
      erlang:monotonic_time() - Begin)
  end.

%% TODO: Add metrics
-spec(check_map(kv()) -> {error, Reason :: term()} | ok).
check_map(NewKV = #kv2{key = Key}) ->
  case erlang:external_size(NewKV) of
    Size when Size > ?REJECT_OBJECT_SIZE_MB * 1000000 ->
      {error, value_too_large};
    Size when Size > (?WARN_OBJECT_SIZE_MB + ?REJECT_OBJECT_SIZE_MB) / 2 * 1000000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes (REJECTION IMMINENT)", [Key, Size]),
      ok;
    Size when Size > ?WARN_OBJECT_SIZE_MB * 1000000 ->
      lager:warning("WARNING: Object '~p' is growing too large at ~p bytes", [Key, Size]),
      ok;
    _ ->
      ok
  end.

-spec (propagate(kv()) -> ok).
propagate(_KV = #kv2{key = Key, map = Map, vclock = VClock}) ->
  Payload = #{type => full_update, reason => op, key => Key, map => Map, vclock => VClock},
  lashup_gm_mc:multicast(?KV_TOPIC, Payload),
  ok.

% @private either gets the KV object for a given key, or returns an empty one
-spec(op_getkv(key()) -> {new, kv()} | {existing, kv()}).
op_getkv(Key) ->
  Begin = erlang:monotonic_time(),
  try mnesia:dirty_read(?KV_TABLE, Key) of
    [] ->
      {new, #kv2{key = Key}};
    [KV] ->
      {existing, KV}
  after
    prometheus_summary:observe(
      lashup, kv_backend_read_seconds, [kv2],
    erlang:monotonic_time() - Begin)
  end.

-spec(op_getkeys(ets:match_spec()) -> [key()]).
op_getkeys(MatchSpec) ->
  Keys = op_dirty_all_keys(?KV_TABLE),
  MatchSpecCompiled = ets:match_spec_compile(MatchSpec),
  [Key || Key <- Keys, [true] == ets:match_spec_run([{Key}], MatchSpecCompiled)].

-spec(op_dirty_all_keys(Table :: atom()) -> [term()]).
op_dirty_all_keys(Table) ->
  prometheus_summary:observe_duration(
    lashup, kv_backend_read_seconds, [Table],
    fun () -> mnesia:dirty_all_keys(Table) end).

-spec(get_lclock(node()) -> lclock()).
get_lclock(Key) ->
  get_lclock(fun mnesia:read/2, Key).

-spec(get_lclock(fun(), node()) -> lclock()).
get_lclock(ReadFun, Key) ->
  Begin = erlang:monotonic_time(),
  try ReadFun(nclock, Key) of
    [] ->
      ?INIT_LCLOCK;
    [#nclock{lclock = LClock}] ->
      LClock
  after
    prometheus_summary:observe(
      lashup, kv_backend_read_seconds, [nclock],
    erlang:monotonic_time() - Begin)
  end.

-spec(handle_lashup_gm_mc_event(map(), state()) -> state()).
handle_lashup_gm_mc_event(#{payload := #{type := full_update} = Payload}, State) ->
  handle_full_update(Payload, State);
handle_lashup_gm_mc_event(Payload, State) ->
  lager:debug("Unknown GM MC event: ~p", [Payload]),
  State.

-spec(mk_full_update_fun(Key :: key(),  RemoteMap :: riak_dt_map:dt_map(),
       RemoteVClock :: riak_dt_vclock:vclock())
       -> fun(() -> kv())).
mk_full_update_fun(Key, RemoteMap, RemoteVClock) ->
  fun() ->
    case mnesia:read(?KV_TABLE, Key, write) of
      [] ->
        LClock0 = get_lclock(node()),
        LClock1 = increment_lclock(LClock0),
        KV = #kv2{key = Key, vclock = RemoteVClock, map = RemoteMap, lclock = LClock1},
        NClock = #nclock{key = node(), lclock = LClock1},
        ok = op_write(KV),
        ok = op_write(NClock),
        KV;
      [KV] ->
        maybe_full_update(should_full_update(KV, RemoteMap, RemoteVClock))
    end
  end.

-spec(maybe_full_update({true | false, kv(), nclock()}) -> kv()).
maybe_full_update({false, KV, _}) ->
  KV;
maybe_full_update({true, KV, NClock}) ->
  ok = op_write(KV),
  ok = op_write(NClock),
  KV.

-spec(should_full_update(LocalKV :: kv(), RemoteMap :: riak_dt_map:dt_map(),
        RemoteVClock :: riak_dt_vclock:vclock())
          -> {true | false, kv(), nclock()}).
should_full_update(LocalKV = #kv2{vclock = LocalVClock}, RemoteMap, RemoteVClock) ->
  case {riak_dt_vclock:descends(RemoteVClock, LocalVClock), riak_dt_vclock:descends(LocalVClock, RemoteVClock)} of
    {true, false} ->
      create_full_update(LocalKV, RemoteMap, RemoteVClock);
    {false, false} ->
      create_full_update(LocalKV, RemoteMap, RemoteVClock);
    %% Either they are equal, or the local one is newer - perhaps trigger AAE?
    _ ->
      LClock0 = get_lclock(node()),
      LClock1 = increment_lclock(LClock0),
      NClock = #nclock{key = node(), lclock = LClock1},
      {false, LocalKV, NClock}
  end.

-spec(create_full_update(LocalKV :: kv(), RemoteMap :: riak_dt_map:dt_map(),
        RemoteVClock :: riak_dt_vclock:vclock()) ->
  {true, kv(), nclock()}).
create_full_update(KV = #kv2{vclock = LocalVClock}, RemoteMap, RemoteVClock) ->
  Map1 =
    prometheus_summary:observe_duration(
      lashup, kv_crdt_op_seconds, [],
      fun () -> riak_dt_map:merge(RemoteMap, KV#kv2.map) end),
  VClock1 = riak_dt_vclock:merge([LocalVClock, RemoteVClock]),
  LClock0 = get_lclock(node()),
  LClock1 = increment_lclock(LClock0),
  KV1 = KV#kv2{map = Map1, vclock = VClock1, lclock = LClock1},
  NClock = #nclock{key = node(), lclock = LClock1},
  {true, KV1, NClock}.

-spec(handle_full_update(map(), state()) -> state()).
handle_full_update(_Payload = #{key := Key, vclock := RemoteVClock, map := RemoteMap}, State) ->
  Begin = erlang:monotonic_time(),
  Fun = mk_full_update_fun(Key, RemoteMap, RemoteVClock),
  {atomic, _} = mnesia:sync_transaction(Fun),
  prometheus_summary:observe(
    lashup, kv_full_update_seconds, [],
    erlang:monotonic_time() - Begin),
  notify_subscribers(Key, State).

increment_lclock(N) ->
  N + 1.

-spec(op_write(tuple()) -> ok).
op_write(Record) ->
  Table = element(1, Record),
  prometheus_summary:observe_duration(
    lashup, kv_backend_write_seconds, [Table],
    fun () -> mnesia:write(Record) end).

%%%===================================================================
%%% Pub/Sub functions
%%%===================================================================

-spec(handle_subscribe(pid(), ets:comp_match_spec(), state()) ->
    {reference(), state()}).
handle_subscribe(Pid, CompMatchSpec, #state{subscribers=Subs}=State) ->
  MonRef = erlang:monitor(process, Pid),
  Subs0 = Subs#{Pid => {CompMatchSpec, MonRef}},
  {MonRef, State#state{subscribers=Subs0}}.

-spec(handle_unsubscribe(pid(), state()) -> state()).
handle_unsubscribe(Pid, #state{subscribers=Subs}=State) ->
  case maps:find(Pid, Subs) of
    {ok, {_CompMatchSpec, MonRef}} ->
      _ = erlang:demonitor(MonRef, [flush]),
      State#state{subscribers=maps:remove(Pid, Subs)};
    error ->
      State
  end.

-spec(notify_subscribers(key(), state()) -> state()).
notify_subscribers(Key, #state{subscribers=Subs}=State) ->
  mforeach(fun (Pid, {CompMatchSpec, Ref}) ->
    case ets:match_spec_run([{Key}], CompMatchSpec) of
      [true] -> Pid ! {lashup_kv_event, Ref, Key};
      _Other -> ok
    end
  end, Subs),
  State.

-spec(mforeach(Fun :: fun((Key, Value) -> term()), Map) -> ok
  when Map :: #{Key => Value} | maps:iterator(Key, Value),
       Key :: term(), Value :: term()).
mforeach(Fun, Map) when is_map(Map) ->
  Iter = maps:iterator(Map),
  mforeach(Fun, Iter);
mforeach(Fun, Iter) ->
  case maps:next(Iter) of
    {Key, Value, Iter0} ->
      _Result = Fun(Key, Value),
      mforeach(Fun, Iter0);
    none ->
      ok
  end.

%%%===================================================================
%%% Metrics functions
%%%===================================================================

-spec(init_metrics() -> ok).
init_metrics() ->
  init_op_metrics(),
  init_kv_metrics(),
  init_backend_metrics().

-spec(init_op_metrics() -> ok).
init_op_metrics() ->
  prometheus_summary:new([
    {registry, lashup},
    {name, kv_op_seconds},
    {duration_unit, seconds},
    {help, "The time spent processing KV operations."}
  ]),
  prometheus_summary:new([
    {registry, lashup},
    {name, kv_op_with_latency_seconds},
    {duration_unit, seconds},
    {help, "The time spent waiting for KV operation execution and "
        "actually executing it."}
  ]),
  prometheus_counter:new([
    {registry, lashup},
    {name, kv_message_queue_overflows_total},
    {labels, [type]},
    {help, "Total number of messages dropped due to queue overflows."}
  ]).

-spec(init_kv_metrics() -> ok).
init_kv_metrics() ->
  prometheus_summary:new([
    {registry, lashup},
    {name, kv_full_update_seconds},
    {duration_unit, seconds},
    {help, "The time spent processing KV full updates."}
  ]),
  prometheus_gauge:new([
    {registry, lashup},
    {name, kv_message_queue_length},
    {help, "The length of KV process message box."}
  ]),
  prometheus_summary:new([
    {registry, lashup},
    {name, kv_crdt_op_seconds},
    {duration_unit, seconds},
    {help, "The time spent merging/updating CRDT in KV process."}
  ]).

-spec(init_backend_metrics() -> ok).
init_backend_metrics() ->
  prometheus_summary:new([
    {registry, lashup},
    {name, kv_backend_read_seconds},
    {labels, [table]},
    {duration_unit, seconds},
    {help, "The time spent reading data from KV backend."}
  ]),
  prometheus_summary:new([
    {registry, lashup},
    {name, kv_backend_write_seconds},
    {labels, [table]},
    {duration_unit, seconds},
    {help, "The time spent writing data to KV backend."}
  ]).
