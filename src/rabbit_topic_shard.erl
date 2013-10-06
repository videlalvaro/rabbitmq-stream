-module(rabbit_topic_shard).

-behaviour(gen_server2).

%% -include_lib("kernel/include/inet.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-export([go/0, ensure_shard/1, remove_shard/1, list_queues/1]).

-export([start_link/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(LOGS_EXCHANGE, <<"amq.rabbitmq.log">>).
-define(LOGS_RKEY, <<"info">>).
-define(LOGS_PREFETCH, 10).

-record(state, {params, %% params used to setup the connection
                connection, %% logs consumer connection
                channel, %% logs consumer channel
                logs_queue, %% used to receive node up/down eventss
                consumer_tag, %% logs consumer ctag
                exchange, %% keep track here of the sharded exchange
                sharded_queues = gb_sets:new(), %% for listing/deleting queues
                up_re   = re:compile("^rabbit on node (.*@.*) up\n\$"),
                down_re = re:compile("^rabbit on node (.*@.*) down\n\$")}).

go() -> cast(go).

ensure_shard(XN) -> cast(XN, ensure_shard). %% TODO maybe not needed.
remove_shard(XN) -> cast(XN, remove_shard).
list_queues(XN)  -> call(XN, list_queues).

start_link(Args) ->
    rabbit_log:info("start_link called: ~p~n", [Args]),
    gen_server2:start_link(?MODULE, Args, [{timeout, infinity}]).

init(#exchange{name = XName} = X) ->
    rabbit_log:info("init called: ~p~n", [XName]),
    %% If we are starting up due to a policy change then it's possible
    %% for the exchange to have been deleted before we got here, in which
    %% case it's possible that delete callback would also have been called
    %% before we got here. So check if we still exist.
    case rabbit_exchange:lookup(XName) of
        {ok, X} ->
            % UParams = rabbit_federation_upstream:to_params(Upstream, X),
            Params = #amqp_params_direct{},
            join(rabbit_topic_shards),
            join({rabbit_topic_shards, XName}),
            gen_server2:cast(self(), maybe_go),
            {ok, {not_started, {Params, XName}}};
        {error, not_found} ->
            {stop, gone}
    end.

% init([]) ->
%     mnesia:subscribe(system), %% TODO: maybe we don't need this
%     {ok, UpRe} = re:compile("^rabbit on node (.*@.*) up\n\$"),
%     {ok, DownRe} = re:compile("^rabbit on node (.*@.*) down\n\$"),
%     {ok, Connection} = amqp_connection:start(#amqp_params_direct{}),
%     {ok, Channel} = amqp_connection:open_channel(
%                         Connection, {amqp_direct_consumer, [self()]}),
%     InitialState = #state{connection  = Connection,
%                           channel     = Channel,
%                           exchange    = <<"amq.rabbitmq.log">>,
%                           routing_key = <<"info">>,
%                           up_re       = UpRe,
%                           down_re     = DownRe},
%     State = setup_events_queue(InitialState),
%     setup_consumer(State),
%     {ok, State}.

handle_call(list_queues, _From, State = #state{sharded_queues = Qs}) ->
    {reply, gb_sets:to_list(Qs), State};

handle_call(Msg, _From, State) ->
    {stop, {unexpected_call, Msg}, State}.


handle_cast(maybe_go, S0 = {not_started, _Args}) ->
    case topic_up() of
        true  -> go(S0);
        false -> {noreply, S0}
    end;

handle_cast(go, S0 = {not_started, _Args}) ->
    go(S0);

%% There's a small race - I think we can realise topic is up
%% before 'go' gets invoked. Ignore.
handle_cast(go, State) ->
    {noreply, State};

handle_cast(ensure_shard, State) ->
    {noreply, ensure_sharded_queues(State)};
    
handle_cast(remove_shard, #state{exchange = XName} = State) ->
    {stop, {shard_removed, XName}, internal_remove_shard(State)};

handle_cast(_Msg, State = {not_started, _}) ->
    {noreply, State};

handle_cast(Msg, State) ->
    {stop, {unexpected_cast, Msg}, State}.

handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

handle_info({#'basic.deliver'{}, #amqp_msg{payload = Payload}}, 
             #state{up_re = UpRe, down_re = DownRe, exchange = XName} = State) ->
    io:format("delivery: ~p~n", [Payload]),
    ReOpts = [{capture, all_but_first, binary}],
    case re:run(Payload, UpRe, ReOpts) of
        {match, [UpNodeBin]} ->
            rabbit_log:info("node up: ~p~n", [UpNodeBin]),
            ensure_shard(XName);
            % ensure_sharded_queues(State);
        _ -> ok
    end,
    
    %% TODO: check for node down and remove the queue from the gb_sets
    %% on node up we will ensure that the queue exist and therefore add it to the gb_sets
    case re:run(Payload, DownRe, ReOpts) of
        {match, [DownNodeBin]} ->
            rabbit_log:info("node down: ~p~n", [DownNodeBin]),
            delete_queue(DownNodeBin, State);
        _ -> ok
    end,
    
    {noreply, State};

handle_info(#'basic.cancel'{}, State = #state{params   = Params,
                                              exchange = XName}) ->
    rabbit_topic_shard_util:connection_error(
      local, basic_cancel, Params, XName, State);

handle_info({'DOWN', _Ref, process, Pid, Reason},
            State = #state{channel  = Ch,
                           exchange = XName}) ->
    rabbit_topic_shard_util:handle_down(
      Pid, Reason, Ch, XName, State);

handle_info(Msg, State) ->
    rabbit_log:info("got info msg: ~p~n", [Msg]),
    {stop, {unexpected_info, Msg}, State}.

terminate(_Reason, {not_started, _}) ->
    ok;

terminate(_Reason, #state{connection = Conn}) ->
    rabbit_topic_shard_util:ensure_connection_closed(Conn),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


call(XName, Msg) -> [gen_server2:call(Pid, Msg, infinity) || Pid <- x(XName)].
cast(Msg)        -> [gen_server2:cast(Pid, Msg) || Pid <- all()].
cast(XName, Msg) -> [gen_server2:cast(Pid, Msg) || Pid <- x(XName)].

join(Name) ->
    pg2_fixed:create(Name),
    ok = pg2_fixed:join(Name, self()).

all() ->
    pg2_fixed:create(rabbit_topic_shards),
    pg2_fixed:get_members(rabbit_topic_shards).

x(XName) ->
    pg2_fixed:create({rabbit_topic_shard, XName}),
    pg2_fixed:get_members({rabbit_topic_shard, XName}).

%%----------------------------------------------------------------------------

topic_up() -> is_pid(whereis(rabbit_topic_app)).

%% -------------------------------------------------------------------------------------

%% TODO: Params so far are dummy #amqp_params_direct{}
go(S0 = {not_started, {Params, XName}}) ->
    %% We trap exits so terminate/2 gets called. Note that this is not
    %% in init() since we need to cope with the link getting restarted
    %% during shutdown (when a broker federates with itself), which
    %% means we hang in topic_up() and the supervisor must force
    %% us to exit. We can therefore only trap exits when past that
    %% point. Bug 24372 may help us do something nicer.
    process_flag(trap_exit, true),
    rabbit_topic_shard_util:start_conn_ch(
      fun (Conn, Ch) ->
              State = ensure_sharded_queues(
                        setup_logs_consumer(
                          #state{params     = Params,
                                 connection = Conn,
                                 channel    = Ch,
                                 exchange   = XName})),
              {noreply, State}
      end, Params, XName, S0).

setup_logs_consumer(State = #state{channel = Channel}) ->
    #'queue.declare_ok'{queue = Q} =
        amqp_channel:call(Channel, #'queue.declare'{}),
    #'queue.bind_ok'{} = 
        amqp_channel:call(Channel, #'queue.bind'{queue       = Q,
                                                 exchange    = ?LOGS_EXCHANGE,
                                                 routing_key = ?LOGS_RKEY}),
    amqp_channel:call(Channel, #'basic.qos'{prefetch_count = ?LOGS_PREFETCH}),
    #'basic.consume_ok'{consumer_tag = CTag} =
        amqp_channel:subscribe(Channel, #'basic.consume'{queue = Q, 
                                                         no_ack = true}, self()),
    State#state{logs_queue = Q, consumer_tag = CTag}.

ensure_sharded_queues(#state{exchange = XName} = State) ->
    %% queue needs to be started in the respective node.
    %% connection will be local.
    %% each rabbit_topic_shard will receive the event
    %% and can declare the queue locally
    Node = node(),
    Methods = [
        #'queue.declare'{queue = queue_name(exchange_name(XName), a2b(Node))},
        #'queue.bind'{exchange = exchange_name(XName), 
                      queue = queue_name(exchange_name(XName), a2b(Node)), 
                      routing_key = <<"1000">>}
    ],
    ErrFun = fun(Code, Text) -> 
                {error, Code, Text}
             end,
    R = rabbit_topic_shard_util:disposable_connection_calls(#amqp_params_direct{}, Methods, ErrFun),
    rabbit_log:info("disposable_connection_calls result: ~p~n", [R]),
    State.

exchange_name(#resource{name = XBin}) -> XBin.

queue_name(XName, NodeBin) ->
    <<"topic: ", XName/binary, " - ", NodeBin/binary>>.

internal_remove_shard(State) ->
    State.

a2b(A) -> list_to_binary(atom_to_list(A)).

delete_queue(_DownNodeBin, _State) ->
    %% delete queue only if _DownNodeBin to atom =:= node()
    ok.