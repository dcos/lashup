%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. Feb 2016 10:45 PM
%%%-------------------------------------------------------------------
-module(lashup_nerve_center_ws_handler).
-author("sdhillon").

-export([
  init/3,
  websocket_init/3,
  websocket_handle/3,
  websocket_info/3,
  websocket_terminate/3
]).

-record(state, {}).

init(_, _Req, _Opts) ->
  {upgrade, protocol, cowboy_websocket}.


websocket_init(_Type, Req, _Opts) ->
  {ok, Req, #state{}}.

websocket_handle({text, Msg}, Req, State) ->
  Data = jsx:decode(Msg, [return_maps]),
  case handle_msg(Data, State) of
    {reply, Reply = {text, _}, State1} ->
      {reply, Reply, Req, State1};
    {reply, ReplyBinary, State1} when is_binary(ReplyBinary) ->
      {reply, {text, ReplyBinary}, Req, State1};
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
  lager:debug("Received info: ~p", [Info]),
  {ok, Req, State}.

websocket_terminate(_TerminateReason, _Req, _State) ->
  ok.

handle_msg(Request = #{<<"type">> := <<"subscribe">>}, State) ->
  {Reply, State1} = handle_subscribe(Request, State),
  {reply, Reply, State1}.

%% #{active_view => [foo@3c075477e55e,'r-23778@3c075477e55e',
%'r-29744@3c075477e55e','r-30742@3c075477e55e',
%'r-849@3c075477e55e'],
%metadata => #{ips => [{10,0,1,2}]},
%node => 'r-8018@3c075477e55e',
%time_since_last_heard => 231826},
handle_subscribe(_Request, State) ->
  GlobalMembership = lashup_gm:gm(),
  Nodes = to_nodes(GlobalMembership),
  Reply = #{message_type => initial_state, nodes => Nodes},
  {Reply, State}.

to_nodes(GM) ->
  lists:foldl(fun accumulate_nodes/2, #{}, GM).

accumulate_nodes(_Node = #{node := NodeName, active_view := AV}, Acc) ->
  NodeData = #{active_view => AV, name => NodeName},
  Acc#{NodeName => NodeData}.



