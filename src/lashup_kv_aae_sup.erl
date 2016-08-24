%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. Feb 2016 6:16 PM
%%%-------------------------------------------------------------------
-module(lashup_kv_aae_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1, start_aae/1, receive_aae/2]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

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


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, {{one_for_one, 5, 10}, []}}.


