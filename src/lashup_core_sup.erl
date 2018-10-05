-module(lashup_core_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  {ok, {#{}, [
    ?CHILD(lashup_hyparview_events, worker),
    ?CHILD(lashup_hyparview_ping_handler, worker),
    ?CHILD(lashup_hyparview_membership, worker),
    ?CHILD(lashup_gm_sup, supervisor)
  ]}}.
