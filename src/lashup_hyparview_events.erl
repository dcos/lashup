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
  subscribe/1,
  subscribe/0,
  subscribe/2]).

%% gen_event callbacks
-export([init/1,
  handle_event/2,
  handle_call/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {callback, active_view = ordsets:new(), passive_view = ordsets:new(), monitor_ref = undefined}).

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

subscribe() ->
  subscribe(self()).
subscribe(Pid) when is_pid(Pid) ->
  Fun =
    fun(Event) ->
      Pid ! {lashup_hyparview_event, Event}
    end,
  subscribe(Fun);
subscribe(Fun) when is_function(Fun, 1) ->
  gen_event:add_sup_handler(?SERVER, ?MODULE, [Fun]).

subscribe(Id, Pid) when is_pid(Pid) ->
  Fun =
    fun(Event) ->
      Pid ! {lashup_hyparview_event, Event}
    end,
  subscribe(Id, Fun);
subscribe(Id, Fun) when is_function(Fun, 1) ->
  gen_event:add_sup_handler(?SERVER, {?MODULE, Id}, [Fun]).


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
init([Fun]) ->
  ActiveView = lashup_hyparview_membership:get_active_view(),
  PassiveView = lashup_hyparview_membership:get_passive_view(),
  State1 = #state{callback = Fun},
  State2 = maybe_restore_monitor_ref(State1),
  State3 = State2#state{passive_view = PassiveView, active_view = ActiveView},
  advertise(State2, State3),
  {ok, State3}.

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
handle_event(#{type := view_update, active_view := Active, passive_view := Passive}, State) ->
  State1 = maybe_restore_monitor_ref(State),
  State2 = State1#state{active_view = Active, passive_view = Passive},
  advertise(State, State2),
  {ok, State2}.

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

handle_info({'DOWN', MonitorRef, _, _, _}, State = #state{monitor_ref = MonitorRef}) ->
  %% We should just mark the monitor_ref as undefined
  %% And set active_view, and passive view to empty
  State1 = State#state{monitor_ref = undefined, active_view = [], passive_view = []},
  advertise(State, State1),
  {ok, State};
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

maybe_restore_monitor_ref(State = #state{monitor_ref = undefined}) ->
  Ref = monitor(process, lashup_hyparview_membership),
  State#state{monitor_ref = Ref};
maybe_restore_monitor_ref(State) ->
  State.

advertise(
  _OldState = #state{active_view = _ActiveView1, passive_view = _PassiveView1, callback = CB},
  _NewState = #state{active_view = ActiveView2, passive_view = PassiveView2}) ->
  {ok, Ref} = timer:kill_after(5000),
  CB(#{type => current_views, passive_view => PassiveView2, active_view => ActiveView2}),
  timer:cancel(Ref).
