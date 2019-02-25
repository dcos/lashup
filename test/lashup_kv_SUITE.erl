-module(lashup_kv_SUITE).

-compile({parse_transform, lager_transform}).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-export([
    all/0,
    init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2
]).

-export([
    fetch_keys/1,
    kv_subscribe/1,
    remove_forgiving/1
]).

all() -> [
    fetch_keys,
    kv_subscribe,
    remove_forgiving
].

init_per_suite(Config) ->
    os:cmd(os:find_executable("epmd") ++ " -daemon"),
    {ok, Hostname} = inet:gethostname(),
    case net_kernel:start([list_to_atom("runner@" ++ Hostname), shortnames]) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,
    Config.

end_per_suite(Config) ->
    net_kernel:stop(),
    Config.

init_per_testcase(_, Config) ->
    application:ensure_all_started(lashup),
    Config.

end_per_testcase(_, Config) ->
    application:stop(lashup),
    application:stop(prometheus),
    Config.

fetch_keys(_Config) ->
    Key1 = [a,b,c],
    {ok, _} = lashup_kv:request_op(Key1, {update, 
                  [{update, 
                      {flag, riak_dt_lwwreg}, 
                      {assign, true, erlang:system_time(nano_seconds)}
                  }]
              }),
    Key2 = [a,b,d],
    {ok, _} = lashup_kv:request_op(Key2, {update, 
                  [{update, 
                      {flag, riak_dt_lwwreg}, 
                      {assign, true, erlang:system_time(nano_seconds)}
                  }]
              }),
    Key3 = [x,y,z],
    {ok, _} = lashup_kv:request_op(Key3, {update, 
                  [{update, 
                      {flag, riak_dt_lwwreg},
                      {assign, true, erlang:system_time(nano_seconds)}
                  }]
              }),
    Keys = lashup_kv:keys(ets:fun2ms(fun({[a, b, '_']}) -> true end)),
    true = lists:member(Key1, Keys) and
           lists:member(Key2, Keys) and
           not lists:member(Key3, Keys),
    ok.

kv_subscribe(_Config) ->
    {ok, _} = lashup_kv:request_op(flag, {update, 
                  [{update, 
                      {color, riak_dt_lwwreg}, 
                      {assign, red, erlang:system_time(nano_seconds)}
                  }]
              }),
    {ok, Ref} = lashup_kv_events_helper:start_link(ets:fun2ms(fun({flag}) -> true end)),
    receive
        {lashup_kv_events, #{type := ingest_new, ref := Ref}} ->
            ok
    after 5000 ->
        ct:fail("Nothing received")
    end,
    {ok, _} = lashup_kv:request_op(flag, {update, 
                  [{update, 
                      {color, riak_dt_lwwreg}, 
                      {assign, blue, erlang:system_time(nano_seconds)}
                  }]
              }),
    receive
        {lashup_kv_events, #{type := ingest_update, ref := Ref, value := Value, old_value := OldValue}} ->
            case {Value, OldValue} of
                {[{{color, riak_dt_lwwreg}, blue}], [{{color, riak_dt_lwwreg}, red}]} ->
                    ok;
                Else ->
                    ct:fail("Got wrong old, and new values: ~p", [Else])
            end
    after 5000 ->
        ct:fail("Nothing received")
    end,
    ok.

remove_forgiving(_Config) ->
    Key = [x, y, z],
    Field = {tratataField, riak_dt_lwwreg},
    {ok, _} = lashup_kv:request_op(Key,
                  {update, [{update, Field, {assign, true, erlang:system_time(nano_seconds)}}]}),
    {ok, Map} = lashup_kv:request_op(Key, {update, [{remove, Field}]}),
    {ok, Map} = lashup_kv:request_op(Key, {update, [{remove, Field}]}),
    {ok, Map} = lashup_kv:request_op(Key, {update, [{remove, Field}]}).
