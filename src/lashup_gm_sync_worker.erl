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
-export([handle/2, start_link/1, do_handle/1]).

%%%===================================================================
%%% API
%%%===================================================================
-record(state, {fanout_pid, seed, nodes_checked = []}).

handle(Pid, Seed) ->
  Args = #{lashup_gm_fanout_pid => Pid, seed => Seed},
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
do_handle(#{lashup_gm_fanout_pid := Pid, seed := Seed}) ->
  link(Pid),
  State = #state{fanout_pid = Pid, seed = Seed},
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


handle_node_clock(_NodeClock = #{node_clock := {Node, VClock}},
    State = #state{nodes_checked = NodeChecked, fanout_pid = Pid}) ->
  Key = lashup_utils:nodekey(Node, State#state.seed),
  case ets:lookup(members, Key) of
  [] ->
    State;
  [Member] ->
    State1 = State#state{nodes_checked = [Node|NodeChecked]},
    case lashup_utils:compare_vclocks(Member#member.vclock, VClock) of
      lt ->
        State1;
      equal ->
        State1;
      _ ->
        UpdatedNode = to_event(Member),
        CompressedTerm = term_to_binary(UpdatedNode, [compressed]),
        erlang:send(Pid, {event, CompressedTerm}, [noconnect]),
        State1
    end
  end.

send_member(Node, State = #state{fanout_pid = Pid}) ->
  Key = lashup_utils:nodekey(Node, State#state.seed),
  case ets:lookup(members, Key) of
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
    node_clock => Member#member.node_clock,
    vclock => Member#member.vclock,
    ttl => 1,
    active_view => Member#member.active_view,
    metadata => Member#member.metadata
  }.