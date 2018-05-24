-module(lashup_kv_sync_rx_fsm).
-author("sdhillon").

-behaviour(gen_statem).

%% API
-export([start_link/2]).


%% Internal APIs
-export([init/1, code_change/4, terminate/3, callback_mode/0]).

-export([rx_sync/3]).

-record(state, {node, monitor_ref, remote_pid}).


start_link(Node, RemotePID) ->
    gen_statem:start_link(?MODULE, [Node, RemotePID], []).

%% Start in the initiator role

init([Node, RemotePid]) ->
    MonitorRef = monitor(process, RemotePid),
    StateData = #state{node = Node, monitor_ref = MonitorRef, remote_pid = RemotePid},
    {ok, rx_sync, StateData, []}.

callback_mode() ->
    state_functions.

code_change(_OldVsn, OldState, OldData, _Extra) ->
    {ok, OldState, OldData}.

terminate(Reason, State, _Data) ->
    lager:warning("KV AAE RX FSM terminated (~p): ~p", [State, Reason]).


rx_sync(info,
        Disconnect = {'DOWN', MonitorRef, _Type, _Object, _Info},
        #state{monitor_ref = MonitorRef}) ->
    handle_disconnect(Disconnect);
rx_sync(info,
        Message = #{key := Key, from := RemotePID, message := keydata, vclock := VClock},
        StateData = #state{remote_pid = RemotePID}) ->
    m_notify(Message),
    case lashup_kv:descends(Key, VClock) of
        false ->
            lager:debug("Synchronizing key ~p from ~p", [Key, node(RemotePID)]),
            request_key(Key, StateData);
        true ->
            ok
    end,
    keep_state_and_data;
rx_sync(info,
        Message = #{from := RemotePID, message := done},
        #state{remote_pid = RemotePID}) ->
    m_notify(Message),
    Reply = #{from => self(), message => rx_sync_complete},
    erlang:send(RemotePID, Reply, [noconnect]),
    erlang:garbage_collect(self()),
    keep_state_and_data;
rx_sync(info, #{from := RemotePID}, #state{remote_pid = RemotePID}) ->
    Message = #{from => self(), message => unknown},
    erlang:send(RemotePID, Message, [noconnect]),
    keep_state_and_data.

request_key(Key, #state{remote_pid = RemotePID}) ->
    #{vclock := VClock, value := Map} = gen_statem:call(RemotePID, {request_key, Key}),
    sync_kv(Key, VClock, Map).

sync_kv(Key, VClock, Map) ->
   gen_server:cast(lashup_kv, {maybe_update, Key, VClock, Map}).


handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, noconnection}) ->
    {stop, normal};
handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, Reason}) ->
    lager:warning("Lashup AAE TX Process disconnected: ~p", [Reason]),
    {stop, normal}.

m_notify(Message) ->
    folsom_metrics:notify({lashup, aae, rx, messages}, {inc, 1}, counter),
    folsom_metrics:notify({lashup, aae, rx, bytes},
                          {inc, erlang:external_size(Message)}, counter).
