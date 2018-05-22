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
  debug_info/1,
  origin/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
  handle_info/2, terminate/2, code_change/3]).

-export_type([topic/0, multicast_packet/0, debug_info/0]).

-record(state, {}).
-type state() :: #state{}.

-type topic() :: atom().
-type payload() :: term().
-type multicast_packet() :: map().
-type mc_opt() :: record_route | loop | {fanout, Fanout :: pos_integer()} |
  {ttl, TTL :: pos_integer()} | {only_nodes, Nodes :: [node()]}.

-type debug_info() :: map().

-define(DEFAULT_TTL, 20).


-spec(multicast(Topic :: topic(), Payload :: payload()) -> ok).
multicast(Topic, Payload) ->
  multicast(Topic, Payload, []).

-spec(multicast(Topic :: topic(), Payload :: payload(), Options :: [mc_opt()]) -> ok).
multicast(Topic, Payload, Options) ->
  [ok = validate_option(Option) || Option <- Options],
  gen_server:cast(?MODULE, {do_multicast, Topic, Payload, Options}).

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

-spec(origin(Packet :: multicast_packet()) -> node()).
origin(Packet) ->
  maps:get(origin, Packet).

-spec(debug_info(Packet :: multicast_packet()) -> debug_info() | false).
debug_info(Packet) ->
  DI =  gather_debug_info(Packet),
  case DI of
    %% This is awkward, and annoying
    %%  #{} = #{foo => bar}.
    Empty when Empty == #{} ->
      false;
    Else ->
      Else
  end.

-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  {ok, #state{}}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(#{type := multicast_packet} = MulticastPacket, State) ->
  handle_multicast_packet(MulticastPacket, State),
  {noreply, State};
handle_cast({do_multicast, Topic, Payload, Options}, State) ->
  handle_do_original_multicast(Topic, Payload, Options, State),
  {noreply, State};
handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(#{type := multicast_packet} = MulticastPacket, State) ->
  handle_multicast_packet(MulticastPacket, State),
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
  Fanout = get_fanout(Options),
  ActiveViewTruncated = determine_fakeroots(ActiveView, Fanout - 1),
  do_original_cast(node(), Packet1),
  %% TODO: Try to make the trees intersect as little as possible
  [do_original_cast(Node, Packet1) || Node <- ActiveViewTruncated],
  ok.

%% @doc
%% determine the fakeroots
%% If the ActiveView is bigger than the fanout, we're going to dump the first node in the active view
%% (lexically sorted).
%% The reason behind this with the BSP Algorithm + Hyparview, it's likely that when the multicast is done
%% treating self = fakeroot, it's going to reach the entire graph
%% Therefore, we want to spread traffic to the upper nodes
%% @end
-spec(determine_fakeroots(ActiveView :: [node()], Fanout :: pos_integer()) -> [node()]).
%% Short circuit
determine_fakeroots([], _) ->
  [];
determine_fakeroots(_, 0) ->
  [];
determine_fakeroots(ActiveView, Fanout) when length(ActiveView) > Fanout ->
  %% We can do this safely, without losing fidelity, because we know the active view
  %% has at least one more member than the fanout
  [_|ActiveView1] = ActiveView,
  Seed = lashup_utils:seed(),
  ActiveView1Shuffled = lashup_utils:shuffle_list(ActiveView1, Seed),
  lists:sublist(ActiveView1Shuffled, Fanout);
determine_fakeroots(ActiveView, _Fanout) ->
  ActiveView.


%% @doc
%% At the original cast, we replicate the packet the size of the active view
%% This is done by reassigning the root for the purposes of the LSA calculation
%% to a surrogate root, (fakeroot)
%% We may want
%% @end
-spec(do_original_cast(node(), multicast_packet()) -> ok).
do_original_cast(Node, Packet) ->
  Packet0 = Packet#{fakeroot => Node},
  Packet1 =
    case lashup_gm_route:get_tree(Node) of
      {tree, Tree} ->
        Packet0#{tree => Tree};
      _ ->
        Packet0
    end,
  gen_server:cast({?MODULE, Node}, Packet1),
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
handle_multicast_packet(MulticastPacket, State) ->
  maybe_forward_packet(MulticastPacket, State),
  maybe_ingest(MulticastPacket),
  ok.

-spec(maybe_ingest(multicast_packet()) -> ok).
maybe_ingest(MulticastPacket = #{only_nodes := Nodes}) ->
  case lists:member(node(), Nodes) of
    true ->
      maybe_ingest2(MulticastPacket);
    false ->
      ok
  end;
maybe_ingest(MulticastPacket) ->
  maybe_ingest2(MulticastPacket).

-spec(maybe_ingest2(multicast_packet()) -> ok).
maybe_ingest2(MulticastPacket = #{origin := Origin, loop := true}) when Origin == node() ->
  lashup_gm_mc_events:ingest(MulticastPacket),
  ok;
maybe_ingest2(_MulticastPacket  = #{origin := Origin}) when Origin == node() ->
  ok;
maybe_ingest2(MulticastPacket) ->
  lashup_gm_mc_events:ingest(MulticastPacket),
  ok.

-spec(maybe_forward_packet(multicast_packet(), state()) -> ok).
maybe_forward_packet(_MulticastPacket = #{ttl := 0, no_ttl_warning := true}, _State) ->
  ok;
maybe_forward_packet(_MulticastPacket = #{ttl := 0}, _State) ->
  lager:warning("TTL Exceeded on Multicast Packet"),
  ok;
maybe_forward_packet(MulticastPacket0 = #{tree := Tree, ttl := TTL, options := Options}, State) ->
  MulticastPacket1 = MulticastPacket0#{ttl := TTL - 1},
  MulticastPacket2 = lists:foldl(fun maybe_add_forwarding_options/2, MulticastPacket1, Options),
  forward_packet(MulticastPacket2, Tree, State);
maybe_forward_packet(MulticastPacket0 = #{fakeroot := FakeRoot, ttl := TTL, origin := Origin, options := Options},
    State) ->
  case lashup_gm_route:get_tree(FakeRoot) of
    {tree, Tree} ->
      MulticastPacket1 = MulticastPacket0#{ttl := TTL - 1},
      MulticastPacket2 = lists:foldl(fun maybe_add_forwarding_options/2, MulticastPacket1, Options),
      forward_packet(MulticastPacket2, Tree, State);
    false ->
      lager:warning("Dropping multicast packet due to unknown root: ~p", [Origin]),
      ok
  end.

%% TODO: Only abcast to connected nodes
-spec(forward_packet(multicast_packet(), lashup_gm_route:tree(), state()) -> ok).
forward_packet(MulticastPacket = #{only_nodes := Nodes}, Tree, _State) ->
  Trees = [lashup_gm_route:prune_tree(Node, Tree) || Node <- Nodes],
  Tree1 = lists:foldl(fun maps:merge/2, #{}, Trees),
  Children = lashup_gm_route:reverse_children(node(), Tree1),
  bsend(MulticastPacket, Children),
  ok;
forward_packet(MulticastPacket, Tree, _State) ->
  Children = lashup_gm_route:children(node(), Tree),
  bsend(MulticastPacket, Children),
  ok.

bsend(MulticastPacket, Children) ->
  lists:foreach(
    fun(Child) ->
      case erlang:send({?MODULE, Child}, MulticastPacket, [noconnect]) of
        noconnect ->
          lager:warning("Dropping packet due to stale tree");
        _ ->
          ok
      end
    end, Children).

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
add_option({OptionKey, OptionValue}, Packet = #{options := Options}) ->
  Options1 = [OptionKey|Options],
  Packet#{options := Options1, OptionKey => OptionValue};
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
  ok;
validate_option({only_nodes, Nodes}) ->
  [true = is_atom(Node) || Node <- Nodes],
  ok.
