%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. Feb 2016 4:47 AM
%%%-------------------------------------------------------------------
-module(lashup_gm_mc).
-author("sdhillon").

-behaviour(gen_server).

%% API
-export([
  start_link/0,
  multicast/2,
  multicast/3
]).

%% Packet Manipulation API
-export([
  ensure_payload_decompressed/1,
  topic/1,
  payload/1,
  debug_info/1
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {}).
-type state() :: #state{}.
-type topic() :: atom().
-type payload() :: term().
-type multicast_packet() :: map().
-type mc_opt() :: record_route | loop | {fanout, Fanout :: pos_integer()} | {ttl, TTL :: pos_integer()}.

-type debug_info() :: map().

-export_type([topic/0, multicast_packet/0, debug_info/0]).

-define(DEFAULT_TTL, 20).


%%%===================================================================
%%% API
%%%===================================================================

-spec(multicast(Topic :: topic(), Payload :: payload()) -> ok).
multicast(Topic, Payload) ->
  multicast(Topic, Payload, []).


-spec(multicast(Topic :: topic(), Payload :: payload(), Options :: [mc_opt()]) -> ok).
multicast(Topic, Payload, Options) ->
  [ok = validate_option(Option) || Option <- Options],
  gen_server:cast(?SERVER, {do_multicast, Topic, Payload, Options}).

-spec(ensure_payload_decompressed(Packet :: multicast_packet()) -> multicast_packet()).
ensure_payload_decompressed(Packet = #{compressed_payload := CompresssedPayload}) ->
  Payload = binary_to_term(CompresssedPayload),
  Packet1 = maps:remove(compressed_payload, Packet),
  Packet1#{payload => Payload};
ensure_payload_decompressed(Packet) ->
  Packet.

-spec(topic(Packet :: multicast_packet()) -> topic()).
topic(_Packet = #{topic := Topic}) ->
  Topic.

-spec(payload(Packet :: multicast_packet()) -> payload()).
payload(Packet) ->
  Packet1 = ensure_payload_decompressed(Packet),
  maps:get(payload, Packet1).

-spec(debug_info(Packet :: multicast_packet()) -> debug_info() | false).
debug_info(Packet) ->
  case gather_debug_info(Packet) of
    #{} ->
      false;
    Else ->
      Else
  end.

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
  {ok, #state{}}.

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
handle_cast(#{type := multicast_packet} = MulticastPacket, State) ->
  handle_multicast_packet(MulticastPacket, State),
  {noreply, State};
handle_cast({do_multicast, Topic, Payload, Options}, State) ->
  handle_do_original_multicast(Topic, Payload, Options, State),
  {noreply, State};
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


-spec(new_multicast_packet() -> multicast_packet()).
new_multicast_packet() ->
  #{type => multicast_packet, origin => node(), ttl => ?DEFAULT_TTL, options => []}.

-spec(new_multicast_packet(Topic :: topic(), Payload :: payload()) -> multicast_packet()).
new_multicast_packet(Topic, Payload) ->
  Packet = new_multicast_packet(),
  CompresssedPayload = term_to_binary(Payload, [compressed]),
  Packet#{topic => Topic, subtype => multicast, compressed_payload => CompresssedPayload}.

%% TODO:
%%  -Buffer messages if my neighbors / active view are flapping too much
%%  -Experiment with adding the tree that I build to the messages.
%%   Although this will make messages larger, it might be more efficient (I also don't know how much larger)
%%   The tree representation could also be significantly reduced in size rather than the map
%%   Which has a bunch of extraneous metadata

-spec(handle_do_original_multicast(Topic :: topic(), Payload :: payload(), Options :: [mc_opt()], State :: state())
    -> ok).
handle_do_original_multicast(Topic, Payload, Options, _State) ->
  Packet = new_multicast_packet(Topic, Payload),
  Packet1 = lists:foldl(fun add_option/2, Packet, Options),
  ActiveView = lashup_hyparview_membership:get_active_view(),
  Seed = lashup_utils:seed(),
  ActiveViewShuffled = lashup_utils:shuffle_list(ActiveView, Seed),
  Fanout = get_fanout(Options),
  ActiveViewTruncated = lists:sublist(ActiveViewShuffled, Fanout),
  %% The first packet goes to everyone in the active view
  [do_original_cast(Node, Packet1) || Node <- ActiveViewTruncated],
  ok.

%% @doc
%% At the original cast, we replicate the packet the size of the active view
%% This is done by reassigning the root for the purposes of the LSA calculation
%% to a surrogate root, (fakeroot)
%% We may want
%% @end
-spec(do_original_cast(node(), multicast_packet()) -> ok).
do_original_cast(Node, Packet) ->
  Packet1 = Packet#{fakeroot => Node},
  gen_server:cast({?SERVER, Node}, Packet1),
  ok.

-spec(get_fanout(Options :: [mc_opt()]) -> pos_integer()).
get_fanout(Options) ->
  MaybeFanout = [N || {fanout, N} <- Options],
  case MaybeFanout of
    [Number] ->
      Number;
    [] ->
      lashup_config:max_mc_replication()
  end.

%% Steps:
%% 1. Process the packet, and forward it on
%% 2. Fan it out to lashup_gm_mc_events
-spec(handle_multicast_packet(multicast_packet(), state()) -> ok).
handle_multicast_packet(MulticastPacket = #{origin := Origin, loop := true}, State) when Origin == node() ->
  maybe_forward_packet(MulticastPacket, State),
  lashup_gm_mc_events:ingest(MulticastPacket),
  ok;
handle_multicast_packet(MulticastPacket  = #{origin := Origin}, State) when Origin == node() ->
  maybe_forward_packet(MulticastPacket, State),
  ok;
handle_multicast_packet(MulticastPacket, State) ->
  maybe_forward_packet(MulticastPacket, State),
  lashup_gm_mc_events:ingest(MulticastPacket),
  ok.

-spec(maybe_forward_packet(multicast_packet(), state()) -> ok).
maybe_forward_packet(_MulticastPacket = #{ttl := 0, no_ttl_warning := true}, _State) ->
  ok;
maybe_forward_packet(_MulticastPacket = #{ttl := 0}, _State) ->
  lager:warning("TTL Exceeded on Multicast Packet"),
  ok;
maybe_forward_packet(MulticastPacket = #{fakeroot := FakeRoot, ttl := TTL, origin := Origin, options := Options}, State) ->
  case lashup_gm_route:get_tree(FakeRoot) of
    {tree, Tree} ->
      MulticastPacket1 = MulticastPacket#{ttl := TTL - 1},
      MulticastPacket2 = lists:foldl(fun maybe_add_forwarding_options/2, MulticastPacket1, Options),
      forward_packet(MulticastPacket2, Tree, State);
    false ->
      lager:warning("Dropping multicast packet due to unknown root: ~p", [Origin]),
      ok
  end.


-spec(forward_packet(multicast_packet(), lashup_gm_route:tree(), state()) -> ok).
forward_packet(MulticastPacket, Tree, _State) ->
  Children = lashup_gm_route:children(node(), Tree),
  gen_server:abcast(Children, ?SERVER, MulticastPacket),
  ok.


%% @doc
%% Add options is a function that's folded over all the options
%% to potentially augment the packet at initial creation
%% (or whatever else needs to be done)
%% @end
-spec(add_option(Option :: mc_opt(), Packet :: multicast_packet()) -> multicast_packet()).
add_option({ttl, TTL}, Packet) ->
  Packet#{ttl := TTL, no_ttl_warning => true};
add_option({fanout, _N}, Packet) ->
  Packet;
add_option(loop, Packet) ->
  Packet#{loop => true};
add_option(record_route, Packet = #{options := Options}) ->
  Options1 = [record_route|Options],
  Packet#{route => [node()], options := Options1};
add_option(Option, Packet = #{options := Options}) ->
  Options1 = [Option|Options],
  Packet#{options := Options1}.


-spec(maybe_add_forwarding_options(mc_opt(), multicast_packet()) -> multicast_packet()).
maybe_add_forwarding_options(record_route, MulticastPacket = #{route := Route}) ->
  Route1 = [node()|Route],
  MulticastPacket#{route := Route1};
maybe_add_forwarding_options(_Option, MulticastPacket) ->
  MulticastPacket.


-spec(gather_debug_info(Packet :: multicast_packet()) -> debug_info()).
gather_debug_info(Packet) ->
  DebugInfo = #{},
  maybe_add_record_route(DebugInfo, Packet).

-spec(maybe_add_record_route(DebugInfo :: debug_info(), Packet :: multicast_packet()) -> debug_info()).
maybe_add_record_route(DebugInfo, _Packet = #{route := Route}) ->
  ActualRoute = lists:reverse(Route),
  DebugInfo#{route => ActualRoute};
maybe_add_record_route(DebugInfo, _) ->
  DebugInfo.

-spec(validate_option(mc_opt()) -> ok).
validate_option(record_route) ->
  ok;
validate_option(loop) ->
  ok;
%% Should we allow 0-fanout -- I don't think so.
validate_option({fanout, N}) when N > 0 ->
  ok;
validate_option({ttl, N}) when N > 0 ->
  ok.