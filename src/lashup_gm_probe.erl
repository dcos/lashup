%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Jan 2016 9:27 PM
%%%-------------------------------------------------------------------
-module(lashup_gm_probe).
-author("sdhillon").

%% TODO:
%% Probe loop
%% It goes node by node in the global membership table
%% and checks if we have a path to them or not
%% If it doesn't find a path, then it checks if we have a path to the next one or not
%% Up until it hits a node greater the last node it probed

%% This is really only useful for extended partitions
%% Where either side has been partitioned from the other for an extended period of time
%% and
%% API
-export([]).
