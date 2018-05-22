-module(lashup_gm_route_events).
-author("sdhillon").
-behaviour(gen_event).

%% API
-export([
    start_link/0,
    subscribe/0,
    remote_subscribe/1,
    ingest/1
]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2,
    handle_info/2, terminate/2, code_change/3]).

-record(state, {
    reference = erlang:error() :: reference() ,
    pid = erlang:error() :: pid(),
    tree = undefined :: lashup_gm_route:tree() | undefined
}).
-type state() :: #state{}.

-spec(ingest(lashup_gm_route:tree()) -> ok).
ingest(Tree) ->
    %% Because the lashup_gm_route, and lashup_gm_route_events fate-share in the supervisor, we should have the sup
    %% deal with restarting, and during tests, if lashup_gm_route_events isn't running, it should be okay
    catch gen_event:notify(?MODULE, {ingest, Tree}),
    ok.

%% @doc
%% Equivalent to {@link {@module}:remote_subscribe/1} with `Node' set to `node()'
%% @end
-spec(subscribe() -> {ok, reference()} | {'EXIT', term()} | {error, term()}).
subscribe() ->
    remote_subscribe(node()).

%% @doc
%% Subscribes calling process to zero or more topics produced by Node.
%%
%% Processes then get messages like:
%% `{{@module}, #{ref => Reference, payload => Payload}}'
%% @end
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

-spec(start_link() -> {ok, pid()} | {error, {already_started, pid()}}).
start_link() ->
    gen_event:start_link({local, ?MODULE}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

init(State) ->
    self() ! flush,
    {ok, State}.

handle_event({ingest, Tree}, State) ->
    handle_ingest(Tree, State),
    {ok, State};
handle_event(_Event, State) ->
    {ok, State}.

handle_call(_Request, State) ->
    Reply = ok,
    {ok, Reply, State}.

handle_info(flush, State) ->
    lashup_gm_route:flush_events_helper(),
    {ok, State};
handle_info(_Info, State) ->
    {ok, State}.

terminate(_Arg, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec(handle_ingest(lashup_gm_route:tree(), state()) -> state()).
handle_ingest(Tree, State0 = #state{tree = Tree}) ->
    State0;
handle_ingest(Tree, State0 = #state{reference = Reference, pid = Pid}) ->
    Event = #{type => tree, tree => Tree, ref => Reference},
    Pid ! {?MODULE, Event},
    State0#state{tree = Tree}.
