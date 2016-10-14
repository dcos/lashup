%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, Mesosphere, Inc.
%%% @doc
%%% Waits for remote nodes to come up on hyparview, and then starts an
%%% AAE sync FSM with them to attempt to synchronize the data.
%%% @end
%%% Created : 31. Jul 2016 11:11 PM
%%%-------------------------------------------------------------------
-module(lashup_kv_aae_mgr).
-author("sdhillon").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
%% A node must be connected for 30 seconds before we attempt AAE
-define(AAE_AFTER, 30000).

-record(state, {hyparview_event_ref, active_view = []}).
-type state() :: #state{}.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: state()} | {ok, State :: state(), timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    {ok, HyparviewEventsRef} = lashup_hyparview_events:subscribe(),
    timer:send_after(0, refresh),
    {ok, #state{hyparview_event_ref = HyparviewEventsRef}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: state()) ->
    {reply, Reply :: term(), NewState :: state()} |
    {reply, Reply :: term(), NewState :: state(), timeout() | hibernate} |
    {noreply, NewState :: state()} |
    {noreply, NewState :: state(), timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: state()} |
    {stop, Reason :: term(), NewState :: state()}).
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: state()) ->
    {noreply, NewState :: state()} |
    {noreply, NewState :: state(), timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: state()}).
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: state()) ->
    {noreply, NewState :: state()} |
    {noreply, NewState :: state(), timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: state()}).
handle_info({lashup_hyparview_events, #{type := current_views, ref := EventRef, active_view := ActiveView}},
    State0 = #state{hyparview_event_ref = EventRef}) ->
    State1 = State0#state{active_view = ActiveView},
    refresh(ActiveView),
    {noreply, State1};
handle_info(refresh, State = #state{active_view = ActiveView}) ->
    refresh(ActiveView),
    timer:send_after(lashup_config:aae_neighbor_check_interval(), refresh),
    {noreply, State};
handle_info({start_child, Child}, State = #state{active_view = ActiveView}) ->
    maybe_start_child(Child, ActiveView),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: state()) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: state(),
    Extra :: term()) ->
    {ok, NewState :: state()} | {error, Reason :: term()}).
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
    %lists:foreach(fun lashup_kv_aae_sup:start_aae/1, ChildrenToStart).
