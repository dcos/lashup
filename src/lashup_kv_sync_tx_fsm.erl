-module(lashup_kv_sync_tx_fsm).
-author("sdhillon").

-behaviour(gen_statem).

%% API
-export([
    start_link/1,
    init_metrics/0
]).

-export([init/3, tx_sync/3, idle/3]).

%% Internal APIs
-export([init/1, code_change/4, terminate/3, callback_mode/0]).

-include_lib("kernel/include/logger.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-record(state, {node, monitor_ref, remote_pid, lclock, maxclock}).


start_link(Node) ->
    gen_statem:start_link(?MODULE, [Node], []).

%% Start in the initiator role
init([Node]) ->
    case lists:member(Node, nodes()) of
        true ->
            {ok, init, [Node], {timeout, 0, init}};
        false ->
            {stop, node_disconnected}
    end.

callback_mode() ->
    state_functions.

init(timeout, init, [Node]) ->
    case gen_server:call({lashup_kv, Node}, {start_kv_sync_fsm, node(), self()}) of
        {error, unknown_request} ->
            {stop, remote_node_no_aae};
        {error, Reason} ->
            {stop, {other_error, Reason}};
        {ok, RemoteChildPid} ->
            LClock = lashup_kv:read_lclock(Node),
            MonitorRef = monitor(process, RemoteChildPid),
            StateData = #state{node = Node, monitor_ref = MonitorRef,
                remote_pid = RemoteChildPid, lclock = LClock, maxclock = LClock},
            {next_state, tx_sync, StateData, [{next_event, internal, start_sync}]}
    end.

tx_sync(info, Disconnect = {'DOWN', MonitorRef, _Type, _Object, _Info}, #state{monitor_ref = MonitorRef}) ->
    handle_disconnect(Disconnect);

tx_sync({call, From}, {request_key, Key}, _) ->
    #{key := Key, vclock := VClock, value := Value} = lashup_kv:raw_value(Key),
    gen_statem:reply(From, #{vclock => VClock, value => Value}),
    keep_state_and_data;

tx_sync(info, #{from := RemotePID, message := rx_sync_complete},
  StateData = #state{node = Node, remote_pid = RemotePID, maxclock = MaxClock}) ->
    case lashup_kv:write_lclock(Node, MaxClock)  of
        ok ->
            {next_state, idle, StateData, [{next_event, internal, reschedule_sync}]};
        {error, Reason} ->
            {stop, Reason}
    end;

tx_sync(internal, start_sync, StateData = #state{maxclock = MaxClock}) ->
    LClock = MaxClock,
    NextKey = maybe_fetch_next_key(lashup_kv:first_key(), LClock),
    defer_sync_key(NextKey),
    {keep_state, StateData#state{lclock = LClock}};

tx_sync(cast, {sync, '$end_of_table'}, #state{remote_pid = RemotePID}) ->
    finish_sync(RemotePID),
    keep_state_and_data;

tx_sync(cast, {sync, Key}, StateData = #state{remote_pid = RemotePID, lclock = LClock, maxclock = MaxClock0}) ->
    KeyClock = send_key_vclock(Key, RemotePID),
    NextKey = maybe_fetch_next_key(lashup_kv:next_key(Key), LClock),
    defer_sync_key(NextKey),
    MaxClock1 = erlang:max(KeyClock, MaxClock0),
    {keep_state, StateData#state{maxclock = MaxClock1}}.

idle(info, do_sync, StateData = #state{node = RemoteNode}) ->
    ?LOG_INFO("Starting tx sync with ~p", [RemoteNode]),
    {next_state, tx_sync, StateData, [{next_event, internal, start_sync}]};

idle(internal, reschedule_sync, #state{node = RemoteNode}) ->
    BaseAAEInterval = lashup_config:aae_interval(),
    NextSync = trunc(BaseAAEInterval * (1 + rand:uniform())),
    ?LOG_INFO("Scheduling sync with ~p in ~p milliseconds", [RemoteNode, NextSync]),
    timer:send_after(NextSync, do_sync),
    keep_state_and_data;

idle(info, Disconnect = {'DOWN', MonitorRef, _Type, _Object, _Info}, #state{monitor_ref = MonitorRef}) ->
    handle_disconnect(Disconnect).

code_change(_OldVsn, OldState, OldData, _Extra) ->
    {ok, OldState, OldData}.

terminate(Reason, State, _Data) ->
    ?LOG_WARNING("KV AAE TX FSMs terminated (~p): ~p", [State, Reason]).

finish_sync(RemotePID) ->
    erlang:garbage_collect(self()),
    %% This is to ensure that all messages have flushed
    Message = #{from => self(), message => done},
    send(RemotePID, Message).

send_key_vclock(Key, RemotePID) ->
    #{vclock := VClock, lclock := KeyClock} = lashup_kv:raw_value(Key),
    Message = #{from => self(), key => Key, vclock => VClock, message => keydata},
    send(RemotePID, Message),
    KeyClock.

defer_sync_key(Key) ->
    Sleep = trunc((rand:uniform() + 0.5) * 10),
    timer:apply_after(Sleep, gen_statem, cast, [self(), {sync, Key}]).

maybe_fetch_next_key(Key, _) when Key == '$end_of_table' ->
    Key;
maybe_fetch_next_key(Key, LClock) ->
    #{lclock := KeyClock} = lashup_kv:raw_value(Key),
    maybe_fetch_next_key(Key, KeyClock, LClock).

maybe_fetch_next_key(Key, KeyClock, LClock) when KeyClock >= LClock ->
    Key;
maybe_fetch_next_key(Key, _, LClock) ->
    NextKey = lashup_kv:next_key(Key),
    maybe_fetch_next_key(NextKey, LClock).

handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, noconnection}) ->
    {stop, normal};
handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, Reason}) ->
    ?LOG_WARNING("Lashup AAE RX Process disconnected: ~p", [Reason]),
    {stop, normal}.

send(RemotePID, Message) ->
    try
        erlang:send(RemotePID, Message, [noconnect])
    after
        Size = erlang:external_size(Message),
        prometheus_counter:inc(lashup, aae_tx_messages_total, [], 1),
        prometheus_counter:inc(lashup, aae_tx_bytes_total, [], Size)
    end.

%%%===================================================================
%%% Metrics functions
%%%===================================================================

-spec(init_metrics() -> ok).
init_metrics() ->
    prometheus_counter:new([
        {registry, lashup},
        {name, aae_tx_messages_total},
        {help, "Total number of Active Anti-Entropy messages sent by "
            "this node."}
    ]),
    prometheus_counter:new([
        {registry, lashup},
        {name, aae_tx_bytes_total},
        {help, "Total size of Active Anti-Entropy messages in bytes "
            "sent by this node."}
    ]).
