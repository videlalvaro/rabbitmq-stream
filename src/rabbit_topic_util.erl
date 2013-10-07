-module(rabbit_topic_util).

-export([shard/1, maybe_shard_exchanges/0, rpc_call/2]).

-include_lib("amqp_client/include/amqp_client.hrl").

-rabbit_boot_step({rabbit_topic_maybe_shard,
                   [{description, "rabbit topic maybe shard"},
                    {mfa,         {?MODULE, maybe_shard_exchanges, []}},
                    {requires,    recovery}]}).
    
%% only shard consistent hash exchanges.
shard(X = #exchange{type = 'x-consistent-hash'}) ->
    case rabbit_policy:get(<<"topic">>, X) of
        undefined -> false;
        _         -> true
    end;

shard(_X) ->
    false.

maybe_shard_exchanges() ->
    io:format("maybe_shard_exchanges called"),
    maybe_shard_exchanges(<<"/">>),
    ok.

maybe_shard_exchanges(VHost) ->
    R = [rpc_call(X, start_child) || X <- find_exchanges(VHost), shard(X)],
    io:format("maybe_shard_exchanges: ~p~n",[R]).

rpc_call(X, Fun) ->
    [rpc:call(Node, rabbit_topic_shard_sup_sup, Fun, [X]) || 
        Node <- rabbit_mnesia:cluster_nodes(running)].

%%----------------------------------------------------------------------------

find_exchanges(VHost) ->
        rabbit_exchange:list(VHost).