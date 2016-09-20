-module(lashup_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
  ok = exometer:ensure([lashup_gm_mc, with_tree], spiral, []),
  ok = exometer:ensure([lashup_gm_mc, without_tree], spiral, []),
  ok = exometer:ensure([lashup_gm_mc, drop_noconnect], spiral, []),
  lashup_sup:start_link().

stop(_State) ->
  ok.