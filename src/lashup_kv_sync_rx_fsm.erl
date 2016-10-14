-module(lashup_kv_sync_rx_fsm).
-author("sdhillon").

-behaviour(gen_statem).

%% API
-export([start_link/2]).


%% Internal APIs
-export([init/1, code_change/4, terminate/3, callback_mode/0]).

-export([rx_sync/3, idle/3]).

-include("lashup_kv.hrl").
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
    lager:warning("KV AAE terminated (~p): ~p", [State, Reason]).


rx_sync(info, Disconnect = {'DOWN', MonitorRef, _Type, _Object, _Info}, #state{monitor_ref = MonitorRef}) ->
    handle_disconnect(Disconnect);
rx_sync(info, #{key := Key, vclock := VClock, map := Map, from := RemotePID, message := kv},
    #state{remote_pid = RemotePID}) ->
    sync_kv(Key, VClock, Map),
    keep_state_and_data;
rx_sync(info, Message = #{key := Key, from := RemotePID, message := keydata},
        StateData = #state{remote_pid = RemotePID}) ->
    case check_key(Message) of
        true ->
            request_key(Key, StateData);
        false ->
            ok
    end,
    keep_state_and_data;
rx_sync(info, #{from := RemotePID, message := done}, StateData = #state{remote_pid = RemotePID}) ->
    Message = #{from => self(), message => rx_sync_complete},
    erlang:send(RemotePID, Message, [noconnect]),
    {next_state, idle, StateData, []}.

idle(info, #{from := RemotePID, message := start_sync}, StateData = #state{remote_pid = RemotePID}) ->
    {next_state, rx_sync, StateData, []};
idle(info, Disconnect = {'DOWN', MonitorRef, _Type, _Object, _Info}, #state{monitor_ref = MonitorRef}) ->
    handle_disconnect(Disconnect).

check_key(#{key := Key, vclock := RemoteVClock}) ->
    case mnesia:dirty_read(kv, Key) of
        [] ->
            true;
        [#kv{vclock = LocalVClock}] ->
            %% Check if the local VClock is a direct descendant of the remote vclock
            case riak_dt_vclock:descends(LocalVClock, RemoteVClock) of
                true ->
                    false;
                false ->
                    true
            end
    end.

request_key(Key, #state{remote_pid = RemotePID}) ->
    Message = #{from => self(), message => request_key, key => Key},
    erlang:send(RemotePID, Message, [noconnect]).

sync_kv(Key, VClock, Map) ->
   gen_server:cast(lashup_kv, {maybe_update, Key, VClock, Map}).


handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, noconnection}) ->
    {stop, normal};
handle_disconnect({'DOWN', _MonitorRef, _Type, _Object, Reason}) ->
    lager:warning("Lashup AAE TX Process disconnected: ~p", [Reason]),
    {stop, normal}.

