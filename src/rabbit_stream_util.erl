-module(rabbit_stream_util).

-export([shard/1, rpc_call/1, find_exchanges/1]).
-export([queue_for_node/3, list_queues/2, list_queues_on_vhost/1]).
-export([exchange_name/1, make_queue_name/2]).

-include_lib("amqp_client/include/amqp_client.hrl").

%% only shard CH or random exchanges.
shard(X = #exchange{type = 'x-random'}) ->
    shard0(X);
    
shard(X = #exchange{type = 'x-consistent-hash'}) ->
    shard0(X);

shard(_X) ->
    false.

shard0(X) ->
    case rabbit_policy:get(<<"stream">>, X) of
        undefined -> false;
        _         -> true
    end.

rpc_call(X) ->
    [rpc:call(Node, rabbit_stream_shard, ensure_sharded_queues, [X]) || 
        Node <- rabbit_mnesia:cluster_nodes(running)].

queue_for_node(Exchange, Vhost, Node) ->
    Q = make_queue_name(Exchange, a2b(Node)),
    case is_queue_alive(Q, Vhost) of
        true -> {ok, Q};
        false -> {error, not_alive}
    end.

% delete_queues(Exchange, Vhost) ->
%     Qs = list_queues(Exchange).

list_queues(#resource{name = XBin}, Vhost) ->
    list_queues(XBin, Vhost);

list_queues(Exchange, Vhost) ->
    lists:filter(fun (Q) -> 
                     is_queue_alive(Q, Vhost) 
                 end, list_queues0(Exchange)).
    
list_queues_on_vhost(Vhost) ->    
    [list_queues(exchange_name(XName), Vhost) || 
        #'exchange'{name = XName} = X <- find_exchanges(Vhost), shard(X)].

list_queues0(Exchange) ->
    [make_queue_name(Exchange, a2b(N)) ||
        N <- rabbit_mnesia:cluster_nodes(running)].

exchange_name(#resource{name = XBin}) -> XBin.

make_queue_name(#resource{kind = exchange, name = XBin}, Node) ->
    make_queue_name(XBin, Node);
    
make_queue_name(XName, Node) when is_binary (XName), is_binary(Node) ->
    <<"stream: ", XName/binary, " - ", Node/binary>>.

%%----------------------------------------------------------------------------

find_exchanges(VHost) ->
    rabbit_exchange:list(VHost).

a2b(A) -> list_to_binary(atom_to_list(A)).

is_queue_alive(QBin, Vhost) ->
    R = rabbit_misc:r(Vhost, queue, QBin),
    case rabbit_amqqueue:lookup(R) of
        {error,not_found} -> false;
        {ok, _Q}          -> true
    end.