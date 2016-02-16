%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. Feb 2016 10:45 PM
%%%-------------------------------------------------------------------
-module(lashup_nervecenter_ws_handler).
-author("sdhillon").

-export([
  init/3,
  websocket_init/3,
  websocket_handle/3,
  websocket_info/3,
  websocket_terminate/3
]).

-include_lib("lashup/include/lashup.hrl").
-record(state, {
  lashup_gm_events_ref = undefined,
  nervecenter_ref = undefined
}).

init(_, _Req, _Opts) ->
  {upgrade, protocol, cowboy_websocket}.


websocket_init(_Type, Req, _Opts) ->
  {ok, Req, #state{}}.

websocket_handle({text, Msg}, Req, State) ->
  Data = jsx:decode(Msg, [return_maps]),
  case handle_msg(Data, State) of
    {reply, Reply, State1} ->
      Reply1 = {text, jsx:encode(Reply)},
      {reply, Reply1, Req, State1}
  end;
websocket_handle(Data, Req, State) ->
  lager:debug("Received data: ~p", [Data]),
  {ok, Req, State}.

websocket_info({timeout, _Ref, Msg}, Req, State) ->
  {reply, {text, Msg}, Req, State};
websocket_info(Info, Req, State) ->
  case handle_info(Info, State) of
    {reply, Replies, State1} when is_list(Replies) ->
      Reply = [{text, jsx:encode(Reply)} || Reply <- Replies] ,
      {reply, Reply, Req, State1};
    {reply, Reply, State1} ->
      Reply1 = {text, jsx:encode(Reply)},
      {reply, Reply1, Req, State1};
    {noreply, State1} ->
      {ok, Req, State1}
  end.

websocket_terminate(_TerminateReason, _Req, _State) ->
  ok.

handle_info({lashup_gm_events, Event = #{ref := Ref}}, #state{lashup_gm_events_ref = Ref} = State) ->
  handle_lashup_gm_event(Event, State);
handle_info({lashup_gm_mc_event, Event = #{ref := Ref}}, #state{nervecenter_ref = Ref}= State) ->
  handle_nervecenter_event(Event, State);
handle_info(Info, State) ->
  lager:debug("Received info: ~p", [Info]),
  {noreply, State}.



handle_lashup_gm_event(_Event = #{member := Member, old_member := OldMember, type := member_change}, State) ->
  NodeUpdate = node_update(Member),
  Messages = [NodeUpdate],
  TotalActiveView = OldMember#member.active_view ++ Member#member.active_view,
  TotalActiveView1 = lists:usort(TotalActiveView),
  Reply = build_update_message(TotalActiveView1, Messages, State),
  {reply, Reply, State};
handle_lashup_gm_event(_Event = #{member := Member, type := new_member}, State) ->
  Reply = build_update_message(Member, State),
  {reply, Reply, State}.

build_update_message(Member = #member{active_view = ActiveView}, State) ->
  NodeUpdate = node_update(Member),
  Messages = [NodeUpdate],
  build_update_message(ActiveView, Messages, State).

build_update_message([], Messages, _State) ->
  Messages;
build_update_message([ActiveViewMember|ActiveView], Messages, State) ->
  case lashup_gm:lookup_node(ActiveViewMember) of
    error ->
      build_update_message(ActiveView, Messages, State);
    {ok, Member} ->
      Messages1 = [node_update(Member)],
      build_update_message(ActiveView, Messages1, State)
  end.

node_update(#member{} = Member) ->
  ActiveView = Member#member.active_view,
  Node = Member#member.node,
  NodeUpdate = build_node(ActiveView, Node),
  #{message_type => node_update, node_update => NodeUpdate}.



handle_msg(Request = #{<<"type">> := <<"subscribe">>}, State) ->
  {Reply, State1} = handle_subscribe(Request, State),
  {reply, Reply, State1}.

handle_subscribe(_Request, State) ->
  {ok, NervecenterRef} = lashup_gm_mc_events:subscribe([nervecenter]),
  {ok, GMEventsRef} = lashup_gm_events:subscribe(),
  GlobalMembership = lashup_gm:gm(),
  State1 = State#state{lashup_gm_events_ref = GMEventsRef, nervecenter_ref = NervecenterRef},
  Nodes = to_nodes(GlobalMembership),
  Reply = #{message_type => initial_state, nodes => Nodes},
  {Reply, State1}.

to_nodes(GM) ->
  lists:foldl(fun accumulate_nodes/2, #{}, GM).

accumulate_nodes(_Node = #{node := NodeName, active_view := AV}, Acc) ->
  NodeData = build_node(AV, NodeName),
  Acc#{NodeName => NodeData}.

build_node(Name) when is_atom(Name) ->
  Source =
    case Name of
      X when X == node() ->
        true;
      _ ->
        false
    end,
  Reachable = lashup_gm_route:reachable(Name),
  OpaqueData = #{source => Source, reachable => Reachable},
  #{name => Name, opaque => OpaqueData}.

build_node(ActiveView, Name) when is_list(ActiveView) and is_atom(Name) ->
  N = build_node(Name),
  N#{active_view => ActiveView}.



handle_nervecenter_event(_Event = #{origin := Origin, payload := #{rollup := Rollup}}, State) ->
  LatencyPerNode = maps:map(fun(_Key, _Value = #{median := Median}) -> Median end, Rollup),
  Message = #{message_type => latency_update, origin => Origin, to_nodes => LatencyPerNode},
  {reply, Message, State}.


%%% TODO:
%% -Add a reachability update every once in a while


