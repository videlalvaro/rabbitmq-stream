-module(rabbit_topic_util).

-export([shard/1, maybe_shard_exchanges/1, rpc_call/2]).

-include_lib("amqp_client/include/amqp_client.hrl").
    
%% only shard consistent hash exchanges.
shard(X = #exchange{type = 'x-consistent-hash'}) ->
    case rabbit_policy:get(<<"topic">>, X) of
        undefined -> false;
        _         -> true
    end;

shard(X) ->
    rabbit_log:info("tried to shard exchange: ~p~n", [X]),
    false.

maybe_shard_exchanges(<<"/">>) ->
    Xs = find_exchanges(<<"/">>),
    [rpc_call(X, start_child) || X <- Xs, shard(X)].

rpc_call(X, Fun) ->
    Nodes = rabbit_mnesia:cluster_nodes(running),
    [rpc:call(Node, rabbit_topic_shard_sup_sup, Fun, [X]) || Node <- Nodes].

%%----------------------------------------------------------------------------

find_exchanges(VHost) ->
        rabbit_exchange:list(VHost).