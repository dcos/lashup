-module(lashup_hyparview_events).
-author("sdhillon").
-behaviour(gen_event).

%% API
-export([
  start_link/0,
  subscribe/0,
  remote_subscribe/1,
  ingest/2
]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2,
  handle_info/2, terminate/2, code_change/3]).

-record(state, {
    pid,
    reference,
    active_view = ordsets:new(),
    passive_view = ordsets:new()
}).


-spec(start_link() -> {ok, pid()} | {error, {already_started, pid()}}).
start_link() ->
  gen_event:start_link({local, ?MODULE}).

-spec(subscribe() -> {ok, reference()} | {'EXIT', term()} | {error, term()}).
subscribe() ->
  remote_subscribe(node()).

ingest(ActiveView, PassiveView) ->
  gen_event:notify(?MODULE, {ingest, ActiveView, PassiveView}),
  ok.

-spec(remote_subscribe(Node :: node()) ->
  {ok, reference()} | {'EXIT', term()} | {error, term()}).
remote_subscribe(Node) ->
  Reference = make_ref(),
  State = #state{pid = self(), reference = Reference},
  EventMgrRef = event_mgr_ref(Node),
  case gen_event:add_sup_handler(EventMgrRef, ?MODULE, State) of
    ok ->
      {ok, Reference};
    {'EXIT', Term} ->
      {'EXIT', Term};
    Error ->
      {error, Error}
  end.

event_mgr_ref(Node) when Node == node() ->
  ?MODULE;
event_mgr_ref(Node) ->
  {?MODULE, Node}.


%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

init(State0) ->
  ActiveView = lashup_hyparview_membership:get_active_view(),
  PassiveView = lashup_hyparview_membership:get_passive_view(),
  State1 = State0#state{passive_view = PassiveView, active_view = ActiveView},
  advertise(State1, [], [], ActiveView, PassiveView),
  {ok, State1}.

handle_event({ingest, ActiveView1, PassiveView1},
    State0 = #state{active_view = ActiveView0, passive_view = PassiveView0}) ->
  State1 = State0#state{active_view = ActiveView1, passive_view = PassiveView1},
  advertise(State1, ActiveView0, PassiveView0, ActiveView1, PassiveView1),
  {ok, State1}.

handle_call(_Request, State) ->
  Reply = ok,
  {ok, Reply, State}.

handle_info(Info, State) ->
  lager:warning("Received unknown info: ~p, in state: ~p", [Info, State]),
  {ok, State}.

terminate(_Arg, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

advertise(#state{reference = Reference, pid = Pid}, ActiveView0, PassiveView0, ActiveView1, PassiveView1) ->
  Event = #{type => current_views, ref => Reference, old_passive_view => PassiveView0, old_active_view => ActiveView0,
    passive_view => PassiveView1, active_view => ActiveView1},
  Pid ! {?MODULE, Event},
  ok.
