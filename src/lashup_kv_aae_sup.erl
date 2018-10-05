-module(lashup_kv_aae_sup).
-behaviour(supervisor).

-export([
    start_link/0,
    start_aae/1,
    receive_aae/2
]).
-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_aae(Node) ->
    ChildSpec = #{
        id => {tx, Node},
        start => {lashup_kv_sync_tx_fsm, start_link, [Node]},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [lashup_kv_sync_tx_fsm]
    },
    supervisor:start_child(?MODULE, ChildSpec).

receive_aae(Node, RemotePid) ->
    ChildSpec = #{
        id => {rx, Node, erlang:unique_integer([positive, monotonic])},
        start => {lashup_kv_sync_rx_fsm, start_link, [Node, RemotePid]},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [lashup_kv_sync_fsm]
    },
    supervisor:start_child(?MODULE, ChildSpec).

init([]) ->
    {ok, {#{}, []}}.
