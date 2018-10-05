-module(lashup_config).
-author("sdhillon").

%% These are the constants for the sizes of views from the lashup paper
-define(K, 6).

%% The original C was 1
%% I think for our use-case, we can bump it to 3?
-define(C, 3).
% This number is actually log10(10000)
-define(LOG_TOTAL_MEMBERS, 4).

-define(DEFAULT_ACTIVE_VIEW_SIZE, ?LOG_TOTAL_MEMBERS + ?C).
-define(DEFAULT_PASSIVE_VIEW_SIZE, ?K * (?LOG_TOTAL_MEMBERS + ?C)).
%% The interval that we try to join the contact nodes in milliseconds
-define(DEFAULT_JOIN_INTERVAL, 1000).
-define(DEFAULT_NEIGHBOR_INTERVAL, 10000).

-define(DEFAULT_SHUFFLE_INTERVAL, 60000).

-define(DEFAULT_MAX_PING_MS, 1000).
%% This is here as a "noise floor"
-define(DEFAULT_MIN_PING_MS, 100).

%% LOG_BASE calculated by taking
%% log(?MAX_PING_MS) / ?LOG_BASE ~= ?MAX_PING_MS
-define(DEFAULT_LOG_BASE, 1.007).

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
  aae_after/0,
  join_timeout/0,
  aae_neighbor_check_interval/0,
  shuffle_interval/0,
  active_view_size/0,
  passive_view_size/0,
  join_interval/0,
  neighbor_interval/0,
  min_ping_ms/0,
  max_ping_ms/0,
  ping_log_base/0,
  aae_route_event_wait/0
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
  get_env(arwl, 8).

%% Passive Random Walk Length
-spec(prwl() -> non_neg_integer()).
prwl() ->
  get_env(prwl, 5).

%% How long to wait for net_adm:ping when doing initial join
%% After this it becomes async
-spec(join_timeout() -> non_neg_integer()).
join_timeout() ->
  get_env(join_timeout, 250).

%%
-spec(contact_nodes() -> [node()]).
contact_nodes() ->
  get_env(contact_nodes, []).

%% We handle reactive changes a little bit differently than the paper.
%% In empirical testing, making everything reactive resulted in a thundering herd
%% The protocol period is effectively how many ms we check the protocol for activating reactive changes

-spec(protocol_period() -> non_neg_integer()).
protocol_period() ->
  get_env(protocol_period, 300).


%% The next two variables are to the de-partitioning behaviour
%% full_probe_period shouldn't be lower than 10 minutes, and it's used to probe the global membership table's
%% down nodes

%% Using a probablistic algorithm we try to scan all the unreachable nodes every full_probe_period, without
%% sending more than one probe every min_departition_probe_interval ms

-spec(full_probe_period() -> non_neg_integer()).
full_probe_period() ->
  get_env(full_probe_period, 600000).

-spec(min_departition_probe_interval() -> non_neg_integer()).
min_departition_probe_interval() ->
  get_env(min_departition_probe_interval, 12000).

%% @doc
%% How many extra copies of a message to send through multicast
%% @end
-spec(max_mc_replication() -> pos_integer()).
max_mc_replication() ->
  get_env(max_mc_replication, 2).

%% @doc
%% How often we message our Vector Clocks for AAE in milliseconds
aae_interval() ->
  get_env(aae_interval, 60000).

%% @doc
%% Lashup working directory
work_dir() ->
  %% This is /var/lib/dcos/lashup on DCOS
  WorkDir = get_env(work_dir, "."),
  NodeNameStr = atom_to_list(node()),
  filename:join(WorkDir, NodeNameStr).


%% @doc
%% How often we message our bloom filter for AAE in milliseconds
bloom_interval() ->
  get_env(bloom_interval, 30000).


%% @doc
%% How long we wait until we begin to do AAE
aae_after() ->
  get_env(aae_after, 30000).

%% @doc
%% How often we see if there are any neighbors connected
aae_neighbor_check_interval() ->
  get_env(aae_neighbor_check_interval, 5000).

-spec(shuffle_interval() -> non_neg_integer()).
shuffle_interval() ->
  get_env(default_shuffle_interval, ?DEFAULT_SHUFFLE_INTERVAL).

-spec(join_interval() -> non_neg_integer()).
join_interval() ->
  get_env(join_interval, ?DEFAULT_JOIN_INTERVAL).

-spec(active_view_size() -> non_neg_integer()).
active_view_size() ->
  get_env(active_view_size, ?DEFAULT_ACTIVE_VIEW_SIZE).

-spec(passive_view_size() -> non_neg_integer()).
passive_view_size() ->
  get_env(passive_view_size, ?DEFAULT_PASSIVE_VIEW_SIZE).

-spec(neighbor_interval() -> non_neg_integer()).
neighbor_interval() ->
  get_env(neighbor_interval, ?DEFAULT_NEIGHBOR_INTERVAL).

-spec(min_ping_ms() -> non_neg_integer()).
min_ping_ms() ->
  get_env(min_ping_ms, ?DEFAULT_MIN_PING_MS).

-spec(max_ping_ms() -> non_neg_integer()).
max_ping_ms() ->
  get_env(max_ping_ms, ?DEFAULT_MAX_PING_MS).

-spec(ping_log_base() -> float()).
ping_log_base() ->
  get_env(ping_log_base, ?DEFAULT_LOG_BASE).

-spec(aae_route_event_wait() -> non_neg_integer()).
aae_route_event_wait() ->
  get_env(aae_route_event_wait, 120000). % 2 min

get_env(Var, Default) ->
  application:get_env(lashup, Var, Default).
