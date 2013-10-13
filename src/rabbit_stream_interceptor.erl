-module(rabbit_stream_interceptor).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_stream.hrl").

-behaviour(rabbit_channel_interceptor).

-export([description/0, process_queue_name/2, applies_to/1, priority/0]).

-import(rabbit_stream_util, [a2b/1]).

-rabbit_boot_step({?MODULE,
                   [{description, "stream interceptor"},
                    {mfa, {rabbit_registry, register,
                           [channel_interceptor, <<"stream interceptor">>, ?MODULE]}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).

description() ->
    [{description, <<"Stream interceptor for channel methods">>}].

process_queue_name(#resource{name = QBin, virtual_host = VHost}, QName2) ->
    case mnesia:dirty_read(?STREAM_TABLE, QBin) of
        []  -> 
            %% Queue is not part of a shard, return default QName
            {ok, QName2};
        [#stream{shards_per_node = N}] -> 
            Rand = crypto:rand_uniform(0, N),
            QBin2 = rabbit_stream_util:make_queue_name(QBin, a2b(node()), Rand),
            {ok, rabbit_misc:r(VHost, queue, QBin2)}
    end.

applies_to('basic_consume') -> true;
applies_to(_Other) -> false.

priority() -> 10.