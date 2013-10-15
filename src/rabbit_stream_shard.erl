-module(rabbit_stream_shard).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_stream.hrl").

-export([maybe_shard_exchanges/0, ensure_sharded_queues/1]). 
-export([update_streams/2, update_stream/2, update_named_stream/2]).

-rabbit_boot_step({rabbit_stream_maybe_shard,
                   [{description, "rabbit stream maybe shard"},
                    {mfa,         {?MODULE, maybe_shard_exchanges, []}},
                    {requires,    direct_client},
                    {enables,     networking}]}).

-import(rabbit_stream_util, [a2b/1, exchange_name/1]).

maybe_shard_exchanges() ->
    [maybe_shard_exchanges(V) || V <- rabbit_vhost:list()],
    ok.

maybe_shard_exchanges(VHost) ->
    [rabbit_stream_util:rpc_call(ensure_sharded_queues, [X]) || 
        X <- rabbit_stream_util:sharded_exchanges(VHost)].

update_named_stream(VHost, Name) ->
    [rabbit_stream_util:rpc_call(update_stream, [X, all]) || 
        X <- rabbit_stream_util:sharded_exchanges(VHost), 
        rabbit_stream_util:get_policy(X) =:= Name].

update_streams(VHost, What) ->
    [rabbit_stream_util:rpc_call(update_stream, [X, What]) || 
        X <- rabbit_stream_util:sharded_exchanges(VHost)].

ensure_sharded_queues(#exchange{name = XName} = X) ->
    %% queue needs to be started on the respective node.
    %% connection will be local.
    %% each rabbit_stream_shard will receive the event
    %% and can declare the queue locally
    RKey = rabbit_stream_util:routing_key(X),
    F = fun (N) ->
            QBin = rabbit_stream_util:make_queue_name(
                       exchange_name(XName), a2b(node()), N),
            [#'queue.declare'{queue = QBin, durable = true},
             #'queue.bind'{exchange = exchange_name(XName), 
                           queue = QBin, 
                           routing_key = RKey}]
        end,
    ErrFun = fun(Code, Text) -> 
                {error, Code, Text}
             end,
    SPN = rabbit_stream_util:shards_per_node(X),
    rabbit_stream_amqp_util:disposable_connection_calls(X, 
        lists:flatten(do_n(F, SPN)), ErrFun).

update_stream(X, all) ->
    {ok, Old, _New} = internal_update_stream(X),
    unbind_sharded_queues(Old, X),
    ensure_sharded_queues(X);

update_stream(X, shards_per_node) ->
    internal_update_stream(X),
    ensure_sharded_queues(X).

unbind_sharded_queues(Old, #exchange{name = XName} = X) ->
    XBin = exchange_name(XName),
    OldSPN = Old#stream.shards_per_node,
    OldRKey = Old#stream.routing_key,
    F = fun (N) ->
            QBin = rabbit_stream_util:make_queue_name(
                       XBin, a2b(node()), N),
            [#'queue.unbind'{exchange    = XBin, 
                             queue       = QBin, 
                             routing_key = OldRKey}]
        end,
    ErrFun = fun(Code, Text) -> 
                {error, Code, Text}
             end,
    rabbit_stream_amqp_util:disposable_connection_calls(X, 
        lists:flatten(do_n(F, OldSPN)), ErrFun).

%%----------------------------------------------------------------------------

internal_update_stream(#exchange{name = #resource{name = XBin}} = X) ->
    case rabbit_stream_util:get_policy(X) of
        undefined  -> {error, "Policy Not Found"};
        PolicyName ->
            rabbit_misc:execute_mnesia_transaction(
                fun () ->
                    case mnesia:read(?STREAM_TABLE, PolicyName, write) of
                        [] ->
                            {error, "Stream not found"};
                        [#stream{} = Old] -> 
                            SPN = rabbit_stream_util:shards_per_node(X),
                            RK = rabbit_stream_util:routing_key(X),
                            New = #stream{name = XBin,
                                          shards_per_node = SPN,
                                          routing_key     = RK},
                            mnesia:write(?STREAM_TABLE, New, write),
                            {ok, Old, New}
                    end
                end)
    end.

do_n(F, N) ->
    do_n(F, 0, N, []).
    
do_n(_F, N, N, Acc) ->
    Acc;
do_n(F, Count, N, Acc) ->
    do_n(F, Count+1, N, [F(Count)|Acc]).