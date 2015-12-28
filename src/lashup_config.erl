%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. Dec 2015 10:59 AM
%%%-------------------------------------------------------------------
-module(lashup_config).
-author("sdhillon").

%% API
-export([arwl/0, prwl/0, contact_nodes/0]).

%% Active Random Walk Length
arwl() ->
  application:get_env(lashup, arwl, 6).

% Passive Random Walk Length
prwl() ->
  application:get_env(lashup, prwl, 3).

%%
contact_nodes() ->
  application:get_env(lashup, contact_nodes, []).