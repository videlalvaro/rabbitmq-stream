-module(rabbit_topic_shard2).

-include_lib("amqp_client/include/amqp_client.hrl").

-export([maybe_shard_exchanges/0, ensure_sharded_queues/1]).

-rabbit_boot_step({rabbit_topic_maybe_shard,
                   [{description, "rabbit topic maybe shard"},
                    {mfa,         {?MODULE, maybe_shard_exchanges, []}},
                    {requires,    direct_client},
                    {enables,     networking}]}).

maybe_shard_exchanges() ->
    %% TODO: get an actual vhost.
    maybe_shard_exchanges(<<"/">>),
    ok.

maybe_shard_exchanges(VHost) ->
    [rabbit_topic_util:rpc_call(X) || 
        X <- rabbit_topic_util:find_exchanges(VHost), rabbit_topic_util:shard(X)].

ensure_sharded_queues(#exchange{name = XName}) ->
    %% queue needs to be started on the respective node.
    %% connection will be local.
    %% each rabbit_topic_shard will receive the event
    %% and can declare the queue locally
    Node = node(),
    Methods = [
        #'queue.declare'{queue = rabbit_topic_util:make_queue_name(XName, a2b(Node)),
                         durable = true},
        #'queue.bind'{exchange = rabbit_topic_util:exchange_name(XName), 
                      queue = rabbit_topic_util:make_queue_name(XName, a2b(Node)), 
                      routing_key = <<"1000">>}
    ],
    ErrFun = fun(Code, Text) -> 
                {error, Code, Text}
             end,
    rabbit_topic_amqp_util:disposable_connection_calls(#amqp_params_direct{}, Methods, ErrFun).
    
a2b(A) -> list_to_binary(atom_to_list(A)).