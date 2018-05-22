-module(lashup_gm_worker_sup).
-behaviour(supervisor).

-export([init/1]).
-export([start_link/0]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  {ok, {#{}, []}}.
