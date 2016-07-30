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
-export([
  arwl/0,
  prwl/0,
  contact_nodes/0,
  protocol_period/0,
  full_probe_period/0,
  min_departition_probe_interval/0,
  max_mc_replication/0,
  aae_interval/0,
  work_dir/0,
  bloom_interval/0,
  key_aae_interval/0,
  join_timeout/0
]).

%% @doc
%% the following three config values are hyparview internals
%%  Associated to the join procedure, there are two configuration parameters,
%% named Active Random Walk Length (ARWL), that specifies the maximum number of hops a
%% ForwardJoin request is propagated, and Passive Random Walk Length (PRWL), that specifies
%% at which point in the walk the node is inserted in a passive view. To use these parameters, the
%% ForwardJoin request carries a “time to live” field that is initially set to ARWL and decreased
%% at every hop.

%% Effectively, they're used during the join process to disseminate the joining node into other nodes
%% Contact nodes are the first members of the overlay that the lashup knows about
%% @end


%% Active Random Walk Length
-spec(arwl() -> non_neg_integer()).
arwl() ->
  application:get_env(lashup, arwl, 8).

%% Passive Random Walk Length
-spec(prwl() -> non_neg_integer()).
prwl() ->
  application:get_env(lashup, prwl, 5).

%% How long to wait for net_adm:ping when doing initial join
%% After this it becomes async
-spec(join_timeout() -> non_neg_integer()).
join_timeout() ->
  application:get_env(lashup, join_timeout, 250).

%%
-spec(contact_nodes() -> [node()]).
contact_nodes() ->
  application:get_env(lashup, contact_nodes, []).

%% We handle reactive changes a little bit differently than the paper.
%% In empirical testing, making everything reactive resulted in a thundering herd
%% The protocol period is effectively how many ms we check the protocol for activating reactive changes

-spec(protocol_period() -> non_neg_integer()).
protocol_period() ->
  application:get_env(lashup, protocol_period, 300).


%% The next two variables are to the de-partitioning behaviour
%% full_probe_period shouldn't be lower than 10 minutes, and it's used to probe the global membership table's
%% down nodes

%% Using a probablistic algorithm we try to scan all the unreachable nodes every full_probe_period, without
%% sending more than one probe every min_departition_probe_interval ms

-spec(full_probe_period() -> non_neg_integer()).
full_probe_period() ->
  application:get_env(lashup, full_probe_period, 600000).

-spec(min_departition_probe_interval() -> non_neg_integer()).
min_departition_probe_interval() ->
  application:get_env(lashup, min_departition_probe_interval, 12000).

%% @doc
%% How many extra copies of a message to send through multicast
%% @end
-spec(max_mc_replication() -> pos_integer()).
max_mc_replication() ->
  application:get_env(lashup, max_mc_replication, 1).

%% @doc
%% How often we message our Vector Clocks for AAE in milliseconds
aae_interval() ->
  application:get_env(lashup, aae_interval, 300000).

%% @doc
%% Lashup working directory
work_dir() ->
  %% This is /var/lib/dcos/lashup on DCOS
  WorkDir = application:get_env(lashup, work_dir, "."),
  NodeNameStr = atom_to_list(node()),
  filename:join(WorkDir, NodeNameStr).


%% @doc
%% How often we message our bloom filter for AAE in milliseconds
bloom_interval() ->
  application:get_env(lashup, bloom_interval, 30000).


%% @doc
%% How often we message our bloom filter for AAE in milliseconds
key_aae_interval() ->
  application:get_env(lashup, key_aae_interval, 600000).
