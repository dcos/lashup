-module(lashup_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => rest_for_one}, [
        ?CHILD(lashup_core_sup, supervisor),
        ?CHILD(lashup_platform_sup, supervisor)
    ]}}.
