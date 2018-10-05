-module(lashup_gm_mc_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{}, [
        ?CHILD(lashup_gm_mc, worker),
        ?CHILD(lashup_gm_mc_events, worker)
    ]}}.

