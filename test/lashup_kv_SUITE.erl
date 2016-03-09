%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 08. Mar 2016 8:06 AM
%%%-------------------------------------------------------------------
-module(lashup_kv_SUITE).

-compile({parse_transform, lager_transform}).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).


init_per_suite(Config) ->
  %% this might help, might not...
  os:cmd(os:find_executable("epmd") ++ " -daemon"),
  {ok, Hostname} = inet:gethostname(),
  case net_kernel:start([list_to_atom("runner@" ++ Hostname), shortnames]) of
    {ok, _} -> ok;
    {error, {already_started, _}} -> ok
  end,
  application:ensure_all_started(lashup),
  Config.

end_per_suite(Config) ->
  application:stop(lashup),
  net_kernel:stop(),
  Config.

all() ->
  [kv_subscribe].

kv_subscribe(_Config) ->
  {ok, _} = lashup_kv:request_op(flag,
    {update, [{update, {color, riak_dt_lwwreg}, {assign, red, erlang:system_time(nano_seconds)}}]}),
  {ok, Ref} = lashup_kv_events_helper:start_link(ets:fun2ms(fun({flag}) -> true end)),
  receive
    {lashup_kv_events, #{type := ingest_new, ref := Ref}} ->
      ok
  after 5000 ->
      ct:fail("Nothing received")
  end,
  {ok, _} = lashup_kv:request_op(flag,
    {update, [{update, {color, riak_dt_lwwreg}, {assign, blue, erlang:system_time(nano_seconds)}}]}),
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


