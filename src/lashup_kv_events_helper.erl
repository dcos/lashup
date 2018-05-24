-module(lashup_kv_events_helper).

%% API
-export([
    start_link/1,
    init/2,
    loop/3
]).

%% We significantly simplified the code here by allowing data to flow "backwards"
%% The time between obtaining the table snapshot and subscribing can drop data

%% The matchspec must be in the format fun({Key}) when GuardSpecs -> true end
-spec(start_link(ets:match_spec()) -> {ok, reference()}).
start_link(MatchSpec) ->
    proc_lib:start_link(?MODULE, init, [self(), MatchSpec]).

-spec(init(pid(), ets:match_spec()) -> ok).
init(Pid, MatchSpec) ->
    Ref = make_ref(),
    proc_lib:init_ack(Pid, {ok, Ref}),
    _MonRef = monitor(process, Pid),
    {ok, Spec, Records} = lashup_kv:subscribe(MatchSpec),
    lists:foreach(fun (Record) ->
        send_event(Pid, Ref, Record)
    end, Records),
    proc_lib:hibernate(?MODULE, loop, [Pid, Ref, Spec]).

-spec(loop(pid(), reference(), ets:comp_match_spec()) -> ok).
loop(Pid, Ref, Spec) ->
    receive
        {mnesia_table_event, Event} ->
            Record = lashup_kv:handle_event(Spec, Event),
            send_event(Pid, Ref, Record);
        {'DOWN', _MonRef, process, Pid, Info} ->
            exit(Info);
        Other ->
            lager:warning("Got something unexpected: ~p", [Other])
    end,
    proc_lib:hibernate(?MODULE, loop, [Pid, Ref, Spec]).

-spec(send_event(pid(), reference(), lashup_kv:kv2map() | false) -> ok).
send_event(_Pid, _Ref, false) ->
    ok;
send_event(Pid, Ref, Event) ->
    Type =
        case maps:is_key(old_value, Event) of
            true -> ingest_update;
            false -> ingest_new
        end,
    Pid ! {lashup_kv_events, Event#{type => Type, ref => Ref}},
    ok.
