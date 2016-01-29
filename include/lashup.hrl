%-record(lashup_join_message, {type, payload}).
-record(member, {
  nodekey :: {Key :: integer(), Node :: node()},
  node :: Node :: node(),
  node_clock :: integer(),
  vclock :: riak_dt_vclock:vclock(),
  locally_updated_at = [] :: [integer()],
  clock_deltas = [] :: [integer()],
  active_view = [] :: [node()],
  metadata = erlang:error() :: map()
}).

-type member() :: #member{}.

