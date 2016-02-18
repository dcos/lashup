-type key() :: term().

-record(kv, {
  key = erlang:error() :: key(),
  map = riak_dt_map:new() :: riak_dt_map:dt_map(),
  vclock = vclock:fresh() :: vclock:vclock()
}).