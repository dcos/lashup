%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%% This module is launched when dump_events is called to start the process of syncing the gm data between the two nodes
%%% It's a temporary worker, unlike lashup_gm_fanout
%%% @end
%%% Created : 04. Feb 2016 10:00 PM
%%%-------------------------------------------------------------------
-module(lashup_gm_sync_worker).
-author("sdhillon").

-include_lib("stdlib/include/ms_transform.hrl").
-include("lashup.hrl").

%% API
-export([handle/1, start_link/1, do_handle/1]).

%%%===================================================================
%%% API
%%%===================================================================
-record(state, {fanout_pid, nodes_checked = []}).

handle(Pid) ->
  Args = #{lashup_gm_fanout_pid => Pid},
  ChildSpec = #{
    id => make_ref(),
    start => {?MODULE, start_link, [Args]},
    restart => temporary
  },
  supervisor:start_child(lashup_gm_worker_sup, ChildSpec).



%% @private
start_link(Args) ->
  Opts = [link, {priority, low}],
  %% Basically never full sweep, because the process dies pretty quickly
  Pid = proc_lib:spawn_opt(?MODULE, do_handle, [Args], Opts),
  {ok, Pid}.

%% @private
do_handle(#{lashup_gm_fanout_pid := Pid}) ->
  link(Pid),
  State = #state{fanout_pid = Pid},
  start_exchange(State).

start_exchange(State) ->
  Message = #{type => aae_keys, pid => self()},
  State#state.fanout_pid ! Message,
  do_exchange(State).

do_exchange(State) ->
  receive
    #{type := node_clock} = NodeClock ->
      State1 = handle_node_clock(NodeClock, State),
      do_exchange(State1);
    #{type := node_clock_complete} ->
      finish_exchange(State)
  end.
finish_exchange(State = #state{nodes_checked = NodesChecked}) ->
  NodesCheckedSet = ordsets:from_list(NodesChecked),
  send_unchecked_nodes(NodesCheckedSet, State).


send_unchecked_nodes(NodesCheckedSet, State) ->
  MatchSpec = ets:fun2ms(
    fun(_Member = #member{node = Node}) ->
      Node
    end
  ),
  Members = ets:select(members, MatchSpec),
  MembersList = ordsets:from_list(Members),
  NodesToSend = ordsets:subtract(MembersList, NodesCheckedSet),
  [send_member(Node, State) || Node <- NodesToSend],
  unlink(State#state.fanout_pid).


handle_node_clock(_NodeClock = #{node_clock := {Node, RemoteClock = {_RemoteEpoch, _RemoteClock}}},
    State = #state{nodes_checked = NodeChecked, fanout_pid = Pid}) ->
  case ets:lookup(members, Node) of
  [] ->
    State;
  [Member = #member{value = #{epoch := LocalEpoch, clock := LocalClock}}] ->
    State1 = State#state{nodes_checked = [Node|NodeChecked]},
    case RemoteClock < {LocalEpoch, LocalClock} of
      %% Only send my local version if I have a strictly "newer" clock
      true ->
        send_event(Pid, Member);
      false ->
        ok
    end,
    State1
  end.

send_event(Pid, Member) ->
  UpdatedNode = to_event(Member),
  CompressedTerm = term_to_binary(UpdatedNode, [compressed]),
  erlang:send(Pid, {event, CompressedTerm}, [noconnect]).


send_member(Node, _State = #state{fanout_pid = Pid}) ->
  case ets:lookup(members, Node) of
    [] ->
      ok;
    [Member] ->
      UpdatedNode = to_event(Member),
      CompressedTerm = term_to_binary(UpdatedNode, [compressed]),
      erlang:send(Pid, {event, CompressedTerm}, [noconnect])
  end.


to_event(Member = #member{}) ->
  #{
    message => updated_node,
    node => Member#member.node,
    value => Member#member.value,
    ttl => 1
  }.