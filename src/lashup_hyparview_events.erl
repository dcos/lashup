%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Jan 2016 10:43 AM
%%%-------------------------------------------------------------------
-module(lashup_hyparview_events).
-author("sdhillon").

-behaviour(gen_event).

%% API
-export([start_link/0,
  subscribe/0,
  remote_subscribe/1,
  ingest/2]).

%% gen_event callbacks
-export([init/1,
  handle_event/2,
  handle_call/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {pid, reference, active_view = ordsets:new(), passive_view = ordsets:new()}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates an event manager
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() -> {ok, pid()} | {error, {already_started, pid()}}).
start_link() ->
  gen_event:start_link({local, ?SERVER}).

-spec(subscribe() -> {ok, reference()} | {'EXIT', term()} | {error, term()}).
subscribe() ->
  remote_subscribe(node()).

ingest(ActiveView, PassiveView) ->
  gen_event:notify(?SERVER, {ingest, ActiveView, PassiveView}),
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
  ?SERVER;
event_mgr_ref(Node) ->
  {?SERVER, Node}.


%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a new event handler is added to an event manager,
%% this function is called to initialize the event handler.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(InitArgs :: term()) ->
  {ok, State :: #state{}} |
  {ok, State :: #state{}, hibernate} |
  {error, Reason :: term()}).
init(State0) ->
  ActiveView = lashup_hyparview_membership:get_active_view(),
  PassiveView = lashup_hyparview_membership:get_passive_view(),
  State1 = State0#state{passive_view = PassiveView, active_view = ActiveView},
  advertise(State1, [], [], ActiveView, PassiveView),
  {ok, State1}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives an event sent using
%% gen_event:notify/2 or gen_event:sync_notify/2, this function is
%% called for each installed event handler to handle the event.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_event(Event :: term(), State :: #state{}) ->
  {ok, NewState :: #state{}} |
  {ok, NewState :: #state{}, hibernate} |
  {swap_handler, Args1 :: term(), NewState :: #state{},
    Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
  remove_handler).
handle_event({ingest, ActiveView1, PassiveView1},
    State0 = #state{active_view = ActiveView0, passive_view = PassiveView0}) ->
  State1 = State0#state{active_view = ActiveView1, passive_view = PassiveView1},
  advertise(State1, ActiveView0, PassiveView0, ActiveView1, PassiveView1),
  {ok, State1}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives a request sent using
%% gen_event:call/3,4, this function is called for the specified
%% event handler to handle the request.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), State :: #state{}) ->
  {ok, Reply :: term(), NewState :: #state{}} |
  {ok, Reply :: term(), NewState :: #state{}, hibernate} |
  {swap_handler, Reply :: term(), Args1 :: term(), NewState :: #state{},
    Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
  {remove_handler, Reply :: term()}).
handle_call(_Request, State) ->
  Reply = ok,
  {ok, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for each installed event handler when
%% an event manager receives any other message than an event or a
%% synchronous request (or a system message).
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: term(), State :: #state{}) ->
  {ok, NewState :: #state{}} |
  {ok, NewState :: #state{}, hibernate} |
  {swap_handler, Args1 :: term(), NewState :: #state{},
    Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
  remove_handler).

handle_info(Info, State) ->
  lager:warning("Received unknown info: ~p, in state: ~p", [Info, State]),
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event handler is deleted from an event manager, this
%% function is called. It should be the opposite of Module:init/1 and
%% do any necessary cleaning up.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Args :: (term() | {stop, Reason :: term()} | stop |
remove_handler | {error, {'EXIT', Reason :: term()}} |
{error, term()}), State :: term()) -> term()).
terminate(_Arg, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
  Extra :: term()) ->
  {ok, NewState :: #state{}}).
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