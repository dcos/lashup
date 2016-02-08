%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. Feb 2016 10:20 PM
%%%-------------------------------------------------------------------
-module(lashup_nerve_center_handler).
-author("sdhillon").


%% API
-export([init/3, handle/2, terminate/3]).

-record(state, {}).

init(_Type, Req, _Opts) ->
  {ok, Req, #state{}}.

handle(Req, State) ->
  {ok, Req2} = cowboy_req:reply(200, [
    {<<"content-type">>, <<"text/plain">>}
  ], <<"Hello World!">>, Req),
  {ok, Req2, State}.

terminate(_Reason, _Req, _State) ->
  ok.