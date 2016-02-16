%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 27. Dec 2015 9:22 PM
%%%-------------------------------------------------------------------
-module(lashup).
-author("sdhillon").

%% API
-export([start/0, stop/0]).

start() ->
  application:ensure_all_started(lashup).

stop() ->
  application:stop(lashup).