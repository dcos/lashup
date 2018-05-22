-module(lashup).
-author("sdhillon").

-export([
    start/0,
    stop/0
]).

start() ->
  application:ensure_all_started(lashup).

stop() ->
  application:stop(lashup).
