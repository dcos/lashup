-type key() :: term().

-record(kv, {
  key = erlang:error() :: key(),
  map = riak_dt_map:new() :: riak_dt_map:dt_map(),
  vclock = riak_dt_vclock:fresh(),
  lclock = undefined :: integer()
}).
