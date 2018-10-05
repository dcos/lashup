-module(lashup_gm_events).
-author("sdhillon").
-behaviour(gen_event).

-include("lashup.hrl").

%% API
-export([
  start_link/0,
  subscribe/0,
  remote_subscribe/1,
  ingest/1,
  ingest/2
]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2,
  handle_info/2, terminate/2, code_change/3]).

-record(state, {
  reference = erlang:error() :: reference() ,
  pid = erlang:error() :: pid()
}).
-type state() :: state().


-spec(ingest(member2(), member2()) -> ok).
ingest(OldMember, NewMember) ->
  gen_event:notify(?MODULE, {ingest, OldMember, NewMember}),
  ok.

-spec(ingest(member2()) -> ok).
ingest(Member) ->
  gen_event:notify(?MODULE, {ingest, Member}),
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
  {ok, State}.

handle_event({ingest, Member}, State) ->
  handle_ingest(Member, State),
  {ok, State};
handle_event({ingest, OldMember, NewMember}, State) ->
  handle_ingest(OldMember, NewMember, State),
  {ok, State};
handle_event(_Message, State) ->
  {ok, State}.

handle_call(_Request, State) ->
  Reply = ok,
  {ok, Reply, State}.

handle_info(_Info, State) ->
  {ok, State}.

terminate(_Arg, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

-spec(handle_ingest(member2(), state()) -> ok).
handle_ingest(Member = #member2{}, _State = #state{reference = Reference, pid = Pid}) ->
  Event = #{type => new_member, member => Member, ref => Reference},
  Pid ! {?MODULE, Event},
  ok.

-spec(handle_ingest(member2(), member2(), state()) -> ok).
handle_ingest(OldMember = #member2{}, NewMember = #member2{},
    _State = #state{reference = Reference, pid = Pid}) ->
  Event = #{type => member_change, old_member => OldMember, member => NewMember, ref => Reference},
  Pid ! {?MODULE, Event},
  ok.
