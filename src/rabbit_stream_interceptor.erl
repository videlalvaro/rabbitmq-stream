-module(rabbit_stream_interceptor).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_stream.hrl").

-behaviour(rabbit_channel_interceptor).

-export([description/0, intercept/1, applies_to/1]).

-import(rabbit_stream_util, [a2b/1]).

-rabbit_boot_step({?MODULE,
                   [{description, "stream interceptor"},
                    {mfa, {rabbit_registry, register,
                           [channel_interceptor, <<"stream interceptor">>, ?MODULE]}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).

description() ->
    [{description, <<"Stream interceptor for channel methods">>}].

intercept(#'basic.consume'{queue = QName} = Method) ->
    {ok, QName2} = queue_name(QName),
    Method#'basic.consume'{queue = QName2};

intercept(#'basic.get'{queue = QName} = Method) ->
    {ok, QName2} = queue_name(QName),
    Method#'basic.get'{queue = QName2};

intercept(#'queue.delete'{queue = QName}) ->
    {error, rabbit_misc:format("Can't delete sharded queue: ~p", [QName])};

intercept(#'queue.declare'{queue = QName}) ->
    {error, rabbit_misc:format("Can't declare sharded queue: ~p", [QName])};

intercept(#'queue.bind'{queue = QName}) ->
    {error, rabbit_misc:format("Can't bind sharded queue: ~p", [QName])};

intercept(#'queue.unbind'{queue = QName}) ->
    {error, rabbit_misc:format("Can't unbind sharded queue: ~p", [QName])};

intercept(#'queue.purge'{queue = QName}) ->
    {error, rabbit_misc:format("Can't purge sharded queue: ~p", [QName])}.

applies_to('basic.consume') -> true;
applies_to('basic.get') -> true;
applies_to('queue.delete') -> true;
applies_to('queue.declare') -> true;
applies_to('queue.bind') -> true;
applies_to('queue.unbind') -> true;
applies_to('queue.purge') -> true;
applies_to(_Other) -> false.

%%----------------------------------------------------------------------------

queue_name(QBin) ->
    case mnesia:dirty_read(?STREAM_TABLE, QBin) of
        []  ->
            %% Queue is not part of a shard, return unmodified name
            {ok, QBin};
        [#stream{shards_per_node = N}] ->
            Rand = crypto:rand_uniform(0, N),
            {ok, rabbit_stream_util:make_queue_name(QBin, a2b(node()), Rand)}
    end.
