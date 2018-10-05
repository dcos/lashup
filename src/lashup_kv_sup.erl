-module(lashup_kv_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{}, [
        ?CHILD(lashup_kv, worker),
        ?CHILD(lashup_kv_aae_sup, supervisor),
        ?CHILD(lashup_kv_aae_mgr, worker)
    ]}}.
