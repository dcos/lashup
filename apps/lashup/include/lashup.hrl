%-record(lashup_join_message, {type, payload}).
-record(member, {
  nodekey :: {Key :: integer(), Node :: node()},
  node :: Node :: node(),
  locally_updated_at = [] :: [integer()],
  clock_deltas = [] :: [integer()],
  active_view = erlang:error() :: [node()],
  dvvset = erlang:error() :: dvvset:dvvset(),
  dvvset_value :: lashup_gm_object:lashup_gm_value()
}).

-type member() :: #member{}.

