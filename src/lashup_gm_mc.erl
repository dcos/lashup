-module(lashup_gm_mc).
-author("sdhillon").
-behaviour(gen_server).

%% API
-export([
  start_link/0,
  multicast/2,
  init_metrics/0
]).

%% Packet API
-export([
  topic/1,
  payload/1,
  origin/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
  handle_info/2, terminate/2, code_change/3]).

-export_type([topic/0, payload/0, multicast_packet/0]).

-record(state, {}).

-type topic() :: atom().
-type payload() :: term().
-type multicast_packet() :: map().

-define(DEFAULT_TTL, 20).

-spec(multicast(Topic :: topic(), Payload :: payload()) -> ok).
multicast(Topic, Payload) ->
  gen_server:cast(?MODULE, {do_multicast, Topic, Payload}).

-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% Packet functions
%%%===================================================================

-spec(topic(Packet :: multicast_packet()) -> topic()).
topic(_Packet = #{topic := Topic}) ->
  Topic.

-spec(payload(Packet :: multicast_packet()) -> payload()).
payload(#{payload := Payload}) ->
  Payload;
payload(#{compressed_payload := CompresssedPayload}) ->
  binary_to_term(CompresssedPayload).

-spec(origin(Packet :: multicast_packet()) -> node()).
origin(Packet) ->
  maps:get(origin, Packet).

-spec(new_multicast_packet(topic(), payload()) -> multicast_packet()).
new_multicast_packet(Topic, Payload) ->
  #{
    type => multicast_packet, subtype => multicast,
    origin => node(), topic => Topic, ttl => ?DEFAULT_TTL,
    compressed_payload => term_to_binary(Payload, [compressed]),
    options => []
  }.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
  {ok, #state{}}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(#{type := multicast_packet} = MulticastPacket, State) ->
  handle_multicast_packet(MulticastPacket),
  {noreply, State};
handle_cast({do_multicast, Topic, Payload}, State) ->
  handle_do_original_multicast(Topic, Payload),
  {noreply, State};
handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(#{type := multicast_packet} = MulticastPacket, State) ->
  handle_multicast_packet(MulticastPacket),
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

-spec(handle_do_original_multicast(topic(), payload()) -> ok).
handle_do_original_multicast(Topic, Payload) ->
  Begin = erlang:monotonic_time(),
  try
    original_multicast(Topic, Payload)
  after
    prometheus_summary:observe(
      lashup, mc_multicast_seconds, [],
      erlang:monotonic_time() - Begin)
  end.

%% TODO:
%%  -Buffer messages if my neighbors / active view are flapping too much
%%  -Experiment with adding the tree that I build to the messages.
%%   Although this will make messages larger, it might be more efficient (I also don't know how much larger)
%%   The tree representation could also be significantly reduced in size rather than the map
%%   Which has a bunch of extraneous metadata

-spec(original_multicast(topic(), payload()) -> ok).
original_multicast(Topic, Payload) ->
  Packet = new_multicast_packet(Topic, Payload),
  ActiveView = lashup_hyparview_membership:get_active_view(),
  Fanout = lashup_config:max_mc_replication(),
  ActiveViewTruncated = determine_fakeroots(ActiveView, Fanout - 1),
  Nodes = [node() | ActiveViewTruncated],
  %% TODO: Try to make the trees intersect as little as possible
  lists:foreach(fun (Node) -> do_original_cast(Node, Packet) end, Nodes).

%% @doc
%% determine the fakeroots
%% If the ActiveView is bigger than the fanout, we're going to dump the first node in the active view
%% (lexically sorted).
%% The reason behind this with the BSP Algorithm + Hyparview, it's likely that when the multicast is done
%% treating self = fakeroot, it's going to reach the entire graph
%% Therefore, we want to spread traffic to the upper nodes
%% @end
-spec(determine_fakeroots(ActiveView :: [node()], Fanout :: pos_integer()) -> [node()]).
determine_fakeroots([], _Fanout) ->
  [];
determine_fakeroots(_ActiveView, 0) ->
  [];
determine_fakeroots(ActiveView, Fanout) when length(ActiveView) > Fanout ->
  % We can do this safely, without losing fidelity, because we know the active view
  % has at least one more member than the fanout
  [_|ActiveView1] = ActiveView,
  Seed = lashup_utils:seed(),
  ActiveView1Shuffled = lashup_utils:shuffle_list(ActiveView1, Seed),
  lists:sublist(ActiveView1Shuffled, Fanout);
determine_fakeroots(ActiveView, _Fanout) ->
  ActiveView.

-spec(do_original_cast(node(), multicast_packet()) -> ok).
do_original_cast(Node, Packet) ->
  % At the original cast, we replicate the packet the size of the active view
  % This is done by reassigning the root for the purposes of the LSA calculation
  % to a surrogate root, (fakeroot)
  % We may want
  Packet0 = Packet#{fakeroot => Node},
  Packet1 =
    case lashup_gm_route:get_tree(Node) of
      {tree, Tree} ->
        Packet0#{tree => Tree};
      _ ->
        Packet0
    end,
  bsend(Packet1, [Node]).

-spec(handle_multicast_packet(multicast_packet()) -> ok).
handle_multicast_packet(MulticastPacket) ->
  Size = erlang:external_size(MulticastPacket),
  prometheus_counter:inc(lashup, mc_incoming_packets_total, [], 1),
  prometheus_counter:inc(lashup, mc_incoming_bytes_total, [], Size),
  % 1. Process the packet, and forward it on
  maybe_forward_packet(MulticastPacket),
  % 2. Fan it out to lashup_gm_mc_events
  maybe_ingest(MulticastPacket).

-spec(maybe_ingest(multicast_packet()) -> ok).
maybe_ingest(#{origin := Origin}) when Origin == node() ->
  ok;
maybe_ingest(MulticastPacket) ->
  lashup_gm_mc_events:ingest(MulticastPacket).

-spec(maybe_forward_packet(multicast_packet()) -> ok).
maybe_forward_packet(_MulticastPacket = #{ttl := 0}) ->
  lager:warning("TTL Exceeded on Multicast Packet"),
  ok;
maybe_forward_packet(MulticastPacket0 = #{tree := Tree, ttl := TTL}) ->
  MulticastPacket1 = MulticastPacket0#{ttl := TTL - 1},
  forward_packet(MulticastPacket1, Tree);
maybe_forward_packet(MulticastPacket0 = #{fakeroot := FakeRoot, ttl := TTL, origin := Origin}) ->
  case lashup_gm_route:get_tree(FakeRoot) of
    {tree, Tree} ->
      MulticastPacket1 = MulticastPacket0#{ttl := TTL - 1},
      forward_packet(MulticastPacket1, Tree);
    false ->
      lager:warning("Dropping multicast packet due to unknown root: ~p", [Origin]),
      ok
  end.

-spec(forward_packet(multicast_packet(), lashup_gm_route:tree()) -> ok).
forward_packet(MulticastPacket, Tree) ->
  %% TODO: Only abcast to connected nodes
  Children = lashup_gm_route:children(node(), Tree),
  bsend(MulticastPacket, Children).

bsend(MulticastPacket, Children) ->
  lists:foreach(fun (Child) ->
    case erlang:send({?MODULE, Child}, MulticastPacket, [noconnect]) of
      noconnect ->
        lager:warning("Dropping packet due to stale tree");
      _Result ->
        prometheus_counter:inc(
          lashup, mc_outgoing_bytes_total, [],
          erlang:external_size(MulticastPacket))
    end
  end, Children).

%%%===================================================================
%%% Metrics functions
%%%===================================================================

-spec(init_metrics() -> ok).
init_metrics() ->
  prometheus_summary:new([
    {registry, lashup},
    {name, mc_multicast_seconds},
    {duration_unit, seconds},
    {help, "The time spent sending out multicast packets."}
  ]),
  prometheus_counter:new([
    {registry, lashup},
    {name, mc_outgoing_bytes_total},
    {help, "Total number of multicast packets sent in bytes."}
  ]),
  prometheus_counter:new([
    {registry, lashup},
    {name, mc_incoming_bytes_total},
    {help, "Total number of bytes multicast packets received in bytes."}
  ]),
  prometheus_counter:new([
    {registry, lashup},
    {name, mc_incoming_packets_total},
    {help, "Total number of bytes multicast packets received."}
  ]).
