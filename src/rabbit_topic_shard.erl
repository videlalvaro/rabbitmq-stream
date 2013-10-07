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
                exchange, %% keep track here of the sharded exchange
                sharded_queues = gb_sets:new() %% for listing/deleting queues
                }).

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
            join({rabbit_topic_shard, XName}),
            gen_server2:cast(self(), maybe_go),
            {ok, {not_started, {Params, XName}}};
        {error, not_found} ->
            {stop, gone}
    end.

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

handle_info(Msg, State) ->
    rabbit_log:info("got info msg: ~p~n", [Msg]),
    {stop, {unexpected_info, Msg}, State}.

terminate(_Reason, {not_started, _}) ->
    ok;

terminate(_Reason, _State) ->
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
go({not_started, {Params, XName}}) ->
    State = ensure_sharded_queues(
                #state{params     = Params,
                       exchange   = XName}),
    {noreply, State}.

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