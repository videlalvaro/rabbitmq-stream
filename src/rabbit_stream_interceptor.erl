-module(rabbit_stream_interceptor).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_stream.hrl").

-behaviour(rabbit_channel_interceptor).

-export([description/0, intercept/3, applies_to/1, priority_param/0]).

-import(rabbit_stream_util, [a2b/1]).

-rabbit_boot_step({?MODULE,
                   [{description, "stream interceptor"},
                    {mfa, {rabbit_registry, register,
                           [channel_interceptor, <<"stream interceptor">>, ?MODULE]}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).

description() ->
    [{description, <<"Stream interceptor for channel methods">>}].

intercept('basic_consume', QName, QName2) ->
    queue_name(QName, QName2);

intercept('basic_get', QName, QName2) ->
    queue_name(QName, QName2);

intercept('queue_delete', _Q1, Q2) ->
    {error, rabbit_misc:format("Can't delete sharded queue: ~p", [Q2])};

intercept('queue_declare', _Q1, Q2) ->
    {error, rabbit_misc:format("Can't declare sharded queue: ~p", [Q2])};

intercept('queue_bind', _Q1, Q2) ->
    {error, rabbit_misc:format("Can't bind sharded queue: ~p", [Q2])};

intercept('queue_unbind', _Q1, Q2) ->
    {error, rabbit_misc:format("Can't unbind sharded queue: ~p", [Q2])};

intercept(_Other, _Q1, Q2) ->
    {ok, Q2}.

applies_to('basic_consume') -> true;
applies_to(_Other) -> false.

priority_param() -> <<"stream-method-priority">>.

%%----------------------------------------------------------------------------

queue_name(#resource{name = QBin, virtual_host = VHost}, QName2) ->
    case mnesia:dirty_read(?STREAM_TABLE, QBin) of
        []  -> 
            %% Queue is not part of a shard, return default QName
            {ok, QName2};
        [#stream{shards_per_node = N}] -> 
            Rand = crypto:rand_uniform(0, N),
            QBin2 = rabbit_stream_util:make_queue_name(QBin, a2b(node()), Rand),
            {ok, rabbit_misc:r(VHost, queue, QBin2)}
    end.