-module(lashup_kv_sync_tx_fsm).
-author("sdhillon").

-behaviour(gen_statem).

%% API
-export([start_link/1]).

-export([tx_sync/3, idle/3]).

%% Internal APIs
-export([init/1, code_change/4, terminate/3, callback_mode/0]).

-include("lashup_kv.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-record(state, {node, monitor_ref, remote_pid, lastclock, maxclock}).


start_link(Node) ->
    gen_statem:start_link(?MODULE, [Node], []).

%% Start in the initiator role
init([Node]) ->
    case lists:member(Node, nodes()) of
        true ->
            init2(Node);
        false ->
            {stop, node_disconnected}
    end.

init2(Node) ->
    case gen_server:call({lashup_kv, Node}, {start_kv_sync_fsm, node(), self()}) of
        {error, unknown_request} ->
            {stop, remote_node_no_aae};
        {error, Reason} ->
            {stop, {other_error, Reason}};
        {ok, RemoteChildPid} ->
            init3(RemoteChildPid, Node)
    end.

init3(RemoteChildPid, RemoteNode) ->
    case gen_server:call(lashup_kv, {clock, get, RemoteNode}) of
        {error, unknown_request} ->
            {stop, remote_node_no_aae};
        {error, Reason} ->
            {stop, {other_error, Reason}};
        {ok, Clock} ->
            MonitorRef = monitor(process, RemoteChildPid),
            StateData = #state{node = RemoteNode, monitor_ref = MonitorRef,
                remote_pid = RemoteChildPid, lastclock = Clock, maxclock = Clock},
            {ok, tx_sync, StateData, [{next_event, internal, start_sync}]}
    end.

callback_mode() ->
    state_functions.

tx_sync(info, Disconnect = {'DOWN', MonitorRef, _Type, _Object, _Info}, #state{monitor_ref = MonitorRef}) ->
    handle_disconnect(Disconnect);

tx_sync({call, From}, {request_key, Key}, _) ->
    [#kv2{key = Key, vclock = VClock, map = Map}] = mnesia:dirty_read(kv, Key),
    gen_statem:reply(From, #{vclock => VClock, value => Map}),
    keep_state_and_data;

tx_sync(info, #{from := RemotePID, message := rx_sync_complete},
  StateData0 = #state{node = Node, remote_pid = RemotePID, maxclock = MaxClock}) ->
    case gen_server:call(lashup_kv, {clock, set, Node, MaxClock}) of
        {ok, updated} ->
            StateData1 = StateData0#state{lastclock = MaxClock},
            {next_state, idle, StateData1, [{next_event, internal, reschedule_sync}]};
        {error, Reason} ->
            {stop, Reason}
    end;

tx_sync(internal, start_sync, _StateData = #state{lastclock = LastClock}) ->
    NextKey = maybe_fetch_next_key(mnesia:dirty_first(kv), LastClock),
    defer_sync_key(NextKey),
    keep_state_and_data;

tx_sync(cast, {sync, '$end_of_table'}, #state{remote_pid = RemotePID}) ->
    finish_sync(RemotePID),
    keep_state_and_data;

tx_sync(cast, {sync, Key},
  StateData = #state{remote_pid = RemotePID, lastclock = LastClock, maxclock = MaxClock0}) ->
    KeyClock = send_key_vclock(Key, RemotePID),
    NextKey = maybe_fetch_next_key(mnesia:dirty_next(kv, Key), LastClock),
    defer_sync_key(NextKey),
    MaxClock1 = maybe_update_clock(KeyClock, MaxClock0),
    {keep_state, StateData#state{maxclock = MaxClock1}}.

idle(info, do_sync, StateData = #state{remote_pid = RemotePID}) ->
    lager:info("Starting tx sync with ~p", [node(RemotePID)]),
    {next_state, tx_sync, StateData, [{next_event, internal, start_sync}]};

idle(internal, reschedule_sync, #state{node = RemoteNode}) ->
    BaseAAEInterval = lashup_config:aae_interval(),
    NextSync = trunc(BaseAAEInterval * (1 + rand:uniform())),
    lager:info("Scheduling sync with ~p in ~p milliseconds", [RemoteNode, NextSync]),
    timer:send_after(NextSync, do_sync),
    keep_state_and_data;

idle(info, Disconnect = {'DOWN', MonitorRef, _Type, _Object, _Info}, #state{monitor_ref = MonitorRef}) ->
    handle_disconnect(Disconnect).

code_change(_OldVsn, OldState, OldData, _Extra) ->
    {ok, OldState, OldData}.

terminate(Reason, State, _Data) ->
    lager:warning("KV AAE TX FSMs terminated (~p): ~p", [State, Reason]).

finish_sync(RemotePID) ->
    erlang:garbage_collect(self()),
    %% This is to ensure that all messages have flushed
    Message = #{from => self(), message => done},
    erlang:send(RemotePID, Message, [noconnect]).

send_key_vclock(Key, RemotePID) ->
    [#kv2{vclock = VClock, lclock = KeyClock}] = mnesia:dirty_read(kv, Key),
    Message = #{from => self(), key => Key, vclock => VClock, message => keydata},
    erlang:send(RemotePID, Message, [noconnect]),
    KeyClock.

defer_sync_key(Key) ->
    Sleep = trunc((rand:uniform() + 0.5) * 10),
    timer:apply_after(Sleep, gen_statem, cast, [self(), {sync, Key}]).

maybe_fetch_next_key(Key, _) when Key == '$end_of_table' ->
    Key;
maybe_fetch_next_key(Key, LastClock) ->
    [#kv2{lclock = KeyClock}] = mnesia:dirty_read(kv, Key),
    maybe_fetch_next_key(Key, KeyClock, LastClock).

maybe_fetch_next_key(Key, KeyClock, LastClock) when KeyClock >= LastClock ->
    Key;
maybe_fetch_next_key(Key, _, LastClock) ->
    NextKey = mnesia:dirty_next(kv, Key),
    maybe_fetch_next_key(NextKey, LastClock).

maybe_update_clock(KeyClock, MaxClock) when KeyClock > MaxClock ->
    KeyClock;
maybe_update_clock(_, MaxClock) ->
    MaxClock.

handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, noconnection}) ->
    {stop, normal};
handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, Reason}) ->
    lager:warning("Lashup AAE RX Process disconnected: ~p", [Reason]),
    {stop, normal}.
