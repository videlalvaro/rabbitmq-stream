-module(rabbit_stream_util).

-export([shard/1, shards_per_node/1, rpc_call/1, find_exchanges/1]).
-export([ exchange_name/1, make_queue_name/3, a2b/1]).

-include_lib("amqp_client/include/amqp_client.hrl").
-include ("rabbit_stream.hrl").

%% only shard CH or random exchanges.
shard(X = #exchange{type = 'x-random'}) ->
    shard0(X);

shard(X = #exchange{type = 'x-consistent-hash'}) ->
    shard0(X);

shard(_X) ->
    false.

shard0(X) ->
    case rabbit_policy:get(<<"stream-definition">>, X) of
        undefined -> false;
        _         -> true
    end.

rpc_call(X) ->
    [rpc:call(Node, rabbit_stream_shard, ensure_sharded_queues, [X]) ||
        Node <- rabbit_mnesia:cluster_nodes(running)].

make_queue_name(QBin, NodeBin, QNum) ->
    %% we do this to prevent unprintable characters that might bork the
    %% management pluing when listing queues.
    QNumBin = list_to_binary(lists:flatten(io_lib:format("~p", [QNum]))),
    <<"stream: ", QBin/binary, " - ", NodeBin/binary, " - ", QNumBin/binary>>.

exchange_name(#resource{name = XBin}) -> XBin.

find_exchanges(VHost) ->
    rabbit_exchange:list(VHost).

a2b(A) -> list_to_binary(atom_to_list(A)).

shards_per_node(X) ->
    case rabbit_runtime_parameters:value(
           vhost(X), <<"stream-definition">>, <<"shards-per-node">>) of
        not_found -> ?DEFAULT_SHARDS_NUM;
        N         -> N
    end.

%%----------------------------------------------------------------------------

vhost(                 #resource{virtual_host = VHost})  -> VHost;
vhost(#exchange{name = #resource{virtual_host = VHost}}) -> VHost.