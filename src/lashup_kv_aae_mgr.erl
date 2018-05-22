%%% @doc
%%% Waits for remote nodes to come up on hyparview, and then starts an
%%% AAE sync FSM with them to attempt to synchronize the data.

-module(lashup_kv_aae_mgr).
-author("sdhillon").
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
    handle_info/2, terminate/2, code_change/3]).

%% A node must be connected for 30 seconds before we attempt AAE
-define(AAE_AFTER, 30000).

-record(state, {
    hyparview_event_ref,
    route_event_ref,
    route_event_timer_ref = make_ref(),
    active_view = []
}).


-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    {ok, HyparviewEventsRef} = lashup_hyparview_events:subscribe(),
    {ok, RouteEventsRef} = lashup_gm_route_events:subscribe(),
    timer:send_after(0, refresh),
    {ok, #state{hyparview_event_ref = HyparviewEventsRef, route_event_ref = RouteEventsRef}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({lashup_hyparview_events, #{type := current_views, ref := EventRef, active_view := ActiveView}},
    State0 = #state{hyparview_event_ref = EventRef}) ->
    State1 = State0#state{active_view = ActiveView},
    refresh(ActiveView),
    {noreply, State1};
handle_info({lashup_gm_route_events, #{ref := Ref}},
            State = #state{route_event_ref = Ref, route_event_timer_ref = TimerRef}) ->
    erlang:cancel_timer(TimerRef),
    TimerRef0 = start_route_event_timer(),
    {noreply, State#state{route_event_timer_ref = TimerRef0}};
handle_info({timeout, Ref, route_event}, State = #state{route_event_timer_ref = Ref}) ->
    State0 = handle_route_event(State),
    {noreply, State0};
handle_info(refresh, State = #state{active_view = ActiveView}) ->
    refresh(ActiveView),
    timer:send_after(lashup_config:aae_neighbor_check_interval(), refresh),
    {noreply, State};
handle_info({start_child, Child}, State = #state{active_view = ActiveView}) ->
    maybe_start_child(Child, ActiveView),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

refresh(ActiveView) ->
    AllChildren = supervisor:which_children(lashup_kv_aae_sup),
    TxChildren = [Id || {{tx, Id}, _Child, _Type, _Modules} <- AllChildren],
    ChildrenToStart = ActiveView -- TxChildren,
    lists:foreach(
        fun(Child) ->
            SleepTime = trunc((1 + rand:uniform()) * lashup_config:aae_after()),
            timer:send_after(SleepTime, {start_child, Child})
        end,
        ChildrenToStart).

maybe_start_child(Child, ActiveView) ->
    case lists:member(Child, ActiveView) of
        true ->
            lashup_kv_aae_sup:start_aae(Child);
        false ->
            ok
    end.

handle_route_event(State) ->
    case lashup_gm_route:get_tree(node()) of
        {tree, Tree} ->
            UnreachableNodes = lashup_gm_route:unreachable_nodes(Tree),
            lager:info("Purging nclock for nodes: ~p", [UnreachableNodes]),
            lists:foreach(fun(Node) ->
                              mnesia:dirty_delete(nclock, Node)
                          end,
                          UnreachableNodes),
            State;
         Error ->
            lager:warning("get_tree() call failed ~p", [Error]),
            TimerRef = start_route_event_timer(),
            State#state{route_event_timer_ref = TimerRef}
    end.

start_route_event_timer() ->
    erlang:start_timer(lashup_config:aae_route_event_wait(), self(), route_event).
