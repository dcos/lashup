-record(member, {
  node :: Node :: node(),
  locally_updated_at = [] :: [integer()],
  clock_deltas = [] :: [integer()],
  active_view = erlang:error() :: [node()],
  value = erlang:error() :: map()
}).

-type member() :: #member{}.

