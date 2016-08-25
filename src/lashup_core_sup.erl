%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. Jan 2016 3:37 PM
%%%-------------------------------------------------------------------
-module(lashup_core_sup).
-author("sdhillon").

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
  {ok, { {one_for_all, 5, 10}, [
    ?CHILD(lashup_hyparview_ping_events, worker),
    ?CHILD(lashup_hyparview_events, worker),
    ?CHILD(lashup_hyparview_ping_handler, worker),
    ?CHILD(lashup_hyparview_membership, worker),
    ?CHILD(lashup_gm_sup, supervisor)
  ]} }.

