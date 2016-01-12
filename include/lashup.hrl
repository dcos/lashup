%-record(lashup_join_message, {type, payload}).
-record(member, {nodekey, node, node_clock, vclock, locally_updated_at = [], clock_deltas = [], active_view = [], metadata = erlang:error()}).
