%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. Feb 2016 4:48 AM
%%%-------------------------------------------------------------------
-module(lashup_hyparview_ping_events).
-author("sdhillon").

-behaviour(gen_event).

%% API
-export([start_link/0,
  subscribe/0,
  remote_subscribe/1,
  ingest/1]).

%% gen_event callbacks
-export([init/1,
  handle_event/2,
  handle_call/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
  reference = erlang:error() :: reference() ,
  pid = erlang:error() :: pid()
}).
-type state() :: state().

-include("lashup.hrl").
%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

ingest(PingData) ->
  gen_event:notify(?SERVER, {ingest, PingData}),
  ok.

%% @doc
%% Subscribes a process to zero or more topics
%% Processes then get messages like:
%% {lashup_gm_mc_event, #{ref => Reference, payload => Payload}}
%% @end
-spec(subscribe() -> {ok, reference()} | {'EXIT', term()} | {error, term()}).
subscribe() ->
  remote_subscribe(node()).

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

%%--------------------------------------------------------------------
%% @doc
%% Creates an event manager
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() -> {ok, pid()} | {error, {already_started, pid()}}).
start_link() ->
  gen_event:start_link({local, ?SERVER}).


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
-spec(init(InitArgs :: state()) ->
  {ok, State :: state()} |
  {ok, State :: state(), hibernate} |
  {error, Reason :: term()}).
init(State) ->
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives an event sent using
%% gen_event:notify/2 or gen_event:sync_notify/2, this function is
%% called for each installed event handler to handle the event.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_event(Message :: term(), State :: state()) ->
  {ok, NewState :: state()} |
  {ok, NewState :: state(), hibernate} |
  {swap_handler, Args1 :: term(), NewState :: state(),
    Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
  remove_handler).
%%
handle_event({ingest, PingData}, State) ->
  handle_ingest(PingData, State),
  {ok, State};
handle_event(_Message, State) ->
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives a request sent using
%% gen_event:call/3,4, this function is called for the specified
%% event handler to handle the request.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), State :: state()) ->
  {ok, Reply :: term(), NewState :: state()} |
  {ok, Reply :: term(), NewState :: state(), hibernate} |
  {swap_handler, Reply :: term(), Args1 :: term(), NewState :: state(),
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
-spec(handle_info(Info :: term(), State :: state()) ->
  {ok, NewState :: state()} |
  {ok, NewState :: state(), hibernate} |
  {swap_handler, Args1 :: term(), NewState :: state(),
    Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
  remove_handler).
handle_info(_Info, State) ->
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
-spec(code_change(OldVsn :: term() | {down, term()}, State :: state(),
  Extra :: term()) ->
  {ok, NewState :: state()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec(handle_ingest(term(), state()) -> ok).
handle_ingest(PingData, _State = #state{reference = Reference, pid = Pid}) ->
  Event = #{ping_data => PingData, ref => Reference},
  Pid ! {?MODULE, Event}.

