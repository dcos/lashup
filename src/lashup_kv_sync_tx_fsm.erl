-module(lashup_kv_sync_tx_fsm).
-author("sdhillon").

-behaviour(gen_statem).

%% API
-export([start_link/1]).

-export([tx_sync/3, idle/3, send_key/3]).

%% Internal APIs
-export([init/1, code_change/4, terminate/3, callback_mode/0]).

-include("lashup_kv.hrl").
-record(state, {node, monitor_ref, remote_pid, lclock}).


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
        {ok, RemoteChildPid, LClock} ->
            MonitorRef = monitor(process, RemoteChildPid),
            StateData = #state{node = Node, monitor_ref = MonitorRef, remote_pid = RemoteChildPid, lclock = LClock},
            {ok, tx_sync, StateData, [{next_event, internal, start_sync}]}
    end.

callback_mode() ->
    state_functions.

tx_sync(info, Disconnect = {'DOWN', MonitorRef, _Type, _Object, _Info}, #state{monitor_ref = MonitorRef}) ->
    handle_disconnect(Disconnect);
tx_sync({call, From}, {request_key, Key}, _) ->
    [#kv{key = Key, vclock = VClock, map = Map}] = mnesia:dirty_read(kv, Key),
    gen_statem:reply(From, #{vclock => VClock, value => Map}),
    keep_state_and_data;
tx_sync(info, #{from := RemotePID, message := rx_sync_complete}, StateData = #state{remote_pid = RemotePID}) ->
    {next_state, idle, StateData, [{next_event, internal, reschedule_sync}]};

tx_sync(internal, start_sync, _StateData) ->
    FirstKey = mnesia:dirty_first(kv),
    defer_sync_key(FirstKey),
    keep_state_and_data;

tx_sync(cast, {sync, '$end_of_table'}, StateData) ->
    finish_sync(StateData),
    keep_state_and_data;

tx_sync(cast, {sync, Key}, StateData) ->
    send_key_vclock(Key, StateData),
    NextKey = mnesia:dirty_next(kv, Key),
    defer_sync_key(NextKey),
    keep_state_and_data.

tx_sync(info, #{from := RemotePID, message := rx_sync_complete},
  StateData = #state{node = Node, remote_pid = RemotePID, lclock = LClock}) ->
    case gen_server:call(lashup_kv, {lclock, set, Node, LClock}) of
        {ok, updated} ->
            {next_state, idle, StateData, [{next_event, internal, reschedule_sync}]};
        {error, Reason} ->
            {stop, Reason}
    end;

tx_sync(internal, start_sync, StateData0 = #state{remote_pid = RemotePID, lclock = OldClock}) ->
    case gen_server:call(lashup_kv, {lclock, get, node()}) of
        {ok, LatestClock} when LatestClock > OldClock ->
            start_sync(OldClock, RemotePID),
            finish_sync(StateData0),
            StateData1 = StateData0#state{lclock = LatestClock},
            {keep_state, StateData1};
        _ -> %% no new update
            {next_state, idle, StateData0, [{next_event, internal, reschedule_sync}]}
    end.

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

finish_sync(#state{remote_pid = RemotePID}) ->
    erlang:garbage_collect(self()),
    %% This is to ensure that all messages have flushed
    Message = #{from => self(), message => done},
    erlang:send(RemotePID, Message, [noconnect]).

send_key_vclock(Key, _StateData = #state{remote_pid = RemotePID}) ->
    [#kv{vclock = VClock}] = mnesia:dirty_read(kv, Key),
    Message = #{from => self(), key => Key, vclock => VClock, message => keydata},
    erlang:send(RemotePID, Message, [noconnect]).

defer_sync_key(Key) ->
    Sleep = trunc((rand:uniform() + 0.5) * 10),
    timer:apply_after(Sleep, ?MODULE, send_key, [Key, VClock, RemotePID]).

fetch_latest_records(OldLClock) ->
    MatchSpec = ets:fun2ms(
      fun(KV = #kv2{lclock = LClock}) when LClock > OldLClock ->
        KV
      end
    ),
    lists:keysort(#kv2.lclock, mnesia:dirty_select(kv, MatchSpec)).

start_sync(OldClock, RemotePID) ->
    Records = fetch_latest_records(OldClock),
    lists:foreach(
        fun(#kv2{key = Key, vclock = VClock}) ->
            defer_sync_key(Key, VClock, RemotePID)
        end,
        Records).

handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, noconnection}) ->
    {stop, normal};
handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, Reason}) ->
    lager:warning("Lashup AAE RX Process disconnected: ~p", [Reason]),
    {stop, normal}.


