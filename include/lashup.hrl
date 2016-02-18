-record(member, {
  node :: Node :: node(),
  locally_updated_at = [] :: [integer()],
  clock_deltas = [] :: [integer()],
  active_view = erlang:error() :: [node()],
  dvvset = erlang:error() :: dvvset:dvvset(),
  dvvset_value :: lashup_gm_object:lashup_gm_value()
}).

-type member() :: #member{}.

