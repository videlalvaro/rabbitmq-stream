-module(rabbit_stream_shard).

-include_lib("amqp_client/include/amqp_client.hrl").

-export([maybe_shard_exchanges/0, ensure_sharded_queues/1]).

-rabbit_boot_step({rabbit_stream_maybe_shard,
                   [{description, "rabbit stream maybe shard"},
                    {mfa,         {?MODULE, maybe_shard_exchanges, []}},
                    {requires,    direct_client},
                    {enables,     networking}]}).

-import(rabbit_stream_util, [a2b/1, exchange_name/1]).

maybe_shard_exchanges() ->
    %% TODO: get an actual vhost.
    %% we need to list vhosts and then iterate over it
    %% How to ensure the right credentials?
    %% maybe list policies on vhost, then get the shard ones
    %5 and from there get the list of vhosts.
    maybe_shard_exchanges(<<"/">>),
    ok.

maybe_shard_exchanges(VHost) ->
    [rabbit_stream_util:rpc_call(X) || 
        X <- rabbit_stream_util:find_exchanges(VHost), rabbit_stream_util:shard(X)].

ensure_sharded_queues(#exchange{name = XName} = X) ->
    %% queue needs to be started on the respective node.
    %% connection will be local.
    %% each rabbit_stream_shard will receive the event
    %% and can declare the queue locally
    RKey = rabbit_stream_util:routing_key(X),
    F = fun (N) ->
            QBin = rabbit_stream_util:make_queue_name(exchange_name(XName), a2b(node()), N),
            [#'queue.declare'{queue = QBin, durable = true},
             #'queue.bind'{exchange = exchange_name(XName), 
                           queue = QBin, 
                           routing_key = RKey}]
        end,
    ErrFun = fun(Code, Text) -> 
                {error, Code, Text}
             end,
    SPN = rabbit_stream_util:shards_per_node(X),
    rabbit_stream_amqp_util:disposable_connection_calls(
        #amqp_params_direct{}, lists:flatten(do_n(F, SPN)), ErrFun).

%%----------------------------------------------------------------------------

do_n(F, N) ->
    do_n(F, 0, N, []).
    
do_n(_F, N, N, Acc) ->
    Acc;
do_n(F, Count, N, Acc) ->
    do_n(F, Count+1, N, [F(Count)|Acc]).