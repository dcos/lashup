%%%-------------------------------------------------------------------
%%% @author sdhillon
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%% This is eventually going to be the scaffolding for a hybrid logical clock server
%%% so we can LWW with confidence
%%% RIGHT NOW IT IS ***DISABLED***
%%% @end
%%% Created : 07. Feb 2016 6:23 PM
%%%-------------------------------------------------------------------
-module(lashup_kv_time).
-author("sdhillon").

-behaviour(gen_server).

%% API
-export([start_link/0,
  entries/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).


-record(state, {
  mc_ref = erlang:error() :: reference(),
  rtt_entries = #{}
}).
-record(rtt_entry, {
  sent_timestamp = erlang:error() :: pos_integer(),
  induced_delay = erlang:error() :: pos_integer(),
  remote_timestamp = erlang:error() :: pos_integer(),
  recv_timestamp = erlang:error() :: pos_integer()
}).

-type state() :: #state{}.


-define(TICK_SECS, 300).
-define(MC_TOPIC_TICK, lashup_kv_tick).


%%%===================================================================
%%% API
%%%===================================================================
entries() ->
  gen_server:call(?SERVER, entries).

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
  random:seed(lashup_utils:seed()),
  {ok, Reference} = lashup_gm_mc_events:subscribe([?MC_TOPIC_TICK]),
  reschedule_tick(5),
  State = #state{mc_ref = Reference},
  {ok, State}.

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
handle_call(entries, _From, State = #state{rtt_entries = Entries}) ->
  {reply, Entries, State};
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
handle_info(tick, State) ->
  State1 = handle_tick(State),
  {noreply, State1};
handle_info({lashup_gm_mc_event, _Event = #{origin := Origin, ref := Reference, payload := Payload}},
    State = #state{mc_ref = Reference}) ->
  State1 = handle_mc_event(Origin, Payload, State),
  {noreply, State1};
handle_info(Else, State) ->
  lager:debug("Unknown info: ~p", [Else]),
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

reschedule_tick() ->
  TickTime = erlang:convert_time_unit(?TICK_SECS, seconds, milli_seconds),
  reschedule_tick(TickTime).

reschedule_tick(Time) ->
  RandFloat = random:uniform(),
  Multipler = 1 + round(RandFloat),
  Delay = Multipler * Time,
  timer:send_after(Delay, tick).

handle_tick(State) ->
  reschedule_tick(),
  Payload = #{type => tick, system_time_ms => erlang:system_time(milli_seconds)},
  lashup_gm_mc:multicast(?MC_TOPIC_TICK, Payload, [loop, {fanout, 1}]),
  State.


handle_mc_event(Origin, _Event = #{type := tick, system_time_ms := OriginalTime}, State) ->
  % Sleep up to 100seconds before replying
  RandomSleep = trunc(random:uniform() * 100000),
  Now = erlang:system_time(milli_seconds),
  Reply = #{
    type => tick_reply,
    induced_delay => RandomSleep,
    original_timestamp => OriginalTime,
    node_timestamp => Now
  },
  MCOptions = [{only_nodes, [Origin]}, loop, {fanout, 1}],
  timer:apply_after(RandomSleep, lashup_gm_mc, multicast, [?MC_TOPIC_TICK, Reply, MCOptions]),
  State;
handle_mc_event(Origin,
    _Event =
  #{
    type := tick_reply,
    original_timestamp := OriginalTimestamp,
    induced_delay := InducedDelay,
    node_timestamp := NodeTimestamp
    },
  State = #state{rtt_entries = RTTEntries}) ->
  Now = erlang:system_time(milli_seconds),
  Entry =
  #rtt_entry{
    sent_timestamp = OriginalTimestamp,
    induced_delay = InducedDelay,
    remote_timestamp = NodeTimestamp,
    recv_timestamp = Now
  },
  Entries = maps:get(Origin, RTTEntries, []),
  EntriesTruncated = lists:sublist(Entries, 99),
  NewEntries = [Entry|EntriesTruncated],
  RTTEntries1 = RTTEntries#{Origin => NewEntries},
  State#state{rtt_entries = RTTEntries1}.

