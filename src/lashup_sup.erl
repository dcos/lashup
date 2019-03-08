-module(lashup_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    lashup_kv:init_metrics(),
    lashup_kv_sync_rx_fsm:init_metrics(),
    lashup_kv_sync_tx_fsm:init_metrics(),
    lashup_gm_mc:init_metrics(),
    lashup_gm:init_metrics(),
    lashup_hyparview_membership:init_metrics(),

    {ok, {#{strategy => rest_for_one}, [
        ?CHILD(lashup_core_sup, supervisor),
        ?CHILD(lashup_platform_sup, supervisor)
    ]}}.
