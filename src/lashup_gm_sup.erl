-module(lashup_gm_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{}, [
        ?CHILD(lashup_gm_worker_sup, supervisor),
        ?CHILD(lashup_gm_events, worker),
        ?CHILD(lashup_gm_route, worker),
        ?CHILD(lashup_gm, worker),
        ?CHILD(lashup_gm_route_events, worker),
        ?CHILD(lashup_gm_probe, worker),
        ?CHILD(lashup_gm_mc_sup, supervisor)
    ]}}.

