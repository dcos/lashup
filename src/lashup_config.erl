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
-export([arwl/0, prwl/0, contact_nodes/0, protocol_period/0, ping_timeout/0]).

%% Active Random Walk Length
arwl() ->
  application:get_env(lashup, arwl, 8).

% Passive Random Walk Length
prwl() ->
  application:get_env(lashup, prwl, 5).

%%
contact_nodes() ->
  application:get_env(lashup, contact_nodes, []).

protocol_period() ->
  application:get_env(lashup, protocol_period, 300).

ping_timeout() ->
  application:get_env(lashup, ping_timeout, 100).