-module(lashup_gm_mc_events).
-author("sdhillon").
-behaviour(gen_event).

%% API
-export([
  start_link/0,
  subscribe/1,
  remote_subscribe/2,
  ingest/1
]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2,
  handle_info/2, terminate/2, code_change/3]).

-record(state, {
  reference = erlang:error() :: reference() ,
  topics_set = erlang:error() :: ordsets:ordset(lashup_gm_mc:topic()),
  pid = erlang:error() :: pid()
}).
-type state() :: state().

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

-spec(ingest(lashup_gm_mc:multicast_packet()) -> ok).
ingest(MulticastPacket) ->
  gen_event:notify(?MODULE, {ingest, MulticastPacket}),
  ok.

%% @doc
%% Equivalent to {@link {@module}:remote_subscribe/2} with `Node' set to `node()'
%% @end
-spec(subscribe([lashup_gm_mc:topic()]) -> {ok, reference()} | {'EXIT', term()} | {error, term()}).
subscribe(Topics) ->
  remote_subscribe(node(), Topics).

%% @doc
%% Subscribes calling process to zero or more topics produced by Node.
%%
%% Processes then get messages like:
%% `{{@module}, #{ref => Reference, payload => Payload}}'
%% @end
-spec(remote_subscribe(Node :: node(), [lashup_gm_mc:topic()]) ->
  {ok, reference()} | {'EXIT', term()} | {error, term()}).
remote_subscribe(Node, Topics) ->
  TopicsSet = ordsets:from_list(Topics),
  Reference = make_ref(),
  State = #state{pid = self(), reference = Reference, topics_set = TopicsSet},
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

handle_event({ingest, Message}, State) ->
  handle_ingest(Message, State),
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

-spec(handle_ingest(lashup_gm_mc:multicast_packet(), state()) -> ok).
handle_ingest(Message, State = #state{topics_set = TopicSet}) ->
  Topic = lashup_gm_mc:topic(Message),
  case ordsets:is_element(Topic, TopicSet) of
    true ->
      handle_ingest2(Message, State);
    false ->
      ok
  end.

-spec(handle_ingest2(lashup_gm_mc:multicast_packet(), state()) -> ok).
handle_ingest2(Message, _State = #state{reference = Reference, pid = Pid}) ->
  Payload = lashup_gm_mc:payload(Message),
  Origin = lashup_gm_mc:origin(Message),
  Event = #{payload => Payload, ref => Reference, origin => Origin},
  Event1 = maybe_add_debug_info(Event, Message),
  Pid ! {lashup_gm_mc_event, Event1},
  ok.

-spec(maybe_add_debug_info(map(), lashup_gm_mc:multicast_packet()) -> map()).
maybe_add_debug_info(Event, Message) ->
  case lashup_gm_mc:debug_info(Message) of
    false ->
      Event;
    DebugInfo ->
      Event#{debug_info => DebugInfo}
  end.

