-module(lashup_nervecenter_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
  lashup_nervecenter:start_link(),
  lashup_nervecenter_sup:start_link().

stop(_State) ->
  lashup_nerve_center:stop().

