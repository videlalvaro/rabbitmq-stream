-module(rabbit_stream_exchange_decorator).

-rabbit_boot_step({?MODULE,
                   [{description, "stream exchange decorator"},
                    {mfa, {rabbit_registry, register,
                           [exchange_decorator, <<"stream">>, ?MODULE]}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).
                    
-rabbit_boot_step({rabbit_stream_exchange_decorator_mnesia,
                   [{description, "rabbit stream exchange decorator: mnesia"},
                    {mfa, {?MODULE, setup_schema, []}},
                    {requires, database},
                    {enables, external_infrastructure}]}).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_stream.hrl").

-behaviour(rabbit_exchange_decorator).

-export([description/0, serialise_events/1]).
-export([create/2, delete/3, policy_changed/2,
         add_binding/3, remove_bindings/3, route/2, active_for/1]).
-export([setup_schema/0]).

%%----------------------------------------------------------------------------

setup_schema() ->
    case mnesia:create_table(?STREAM_TABLE,
                             [{attributes, record_info(fields, stream)},
                              {record_name, stream},
                              {type, set}]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, ?STREAM_TABLE}} -> ok
    end.

description() ->
    [{description, <<"Shard exchange decorator">>}].

serialise_events(_X) -> false.

create(transaction, _X) ->
    ok;
create(none, X) ->
    maybe_start(X).

add_binding(_Tx, _X, _B) -> ok.
remove_bindings(_Tx, _X, _Bs) -> ok.

route(_, _) -> [].

active_for(X) ->
    case shard(X) of
        true  -> noroute;
        false -> none
    end.

%% We can't do anything here actually
%% the queues can only be deleted by a queue_delete command
%% since we don't want the user accidentally losing messages
delete(_Tx, _X, _Bs) -> ok.
policy_changed(_OldX, _NewX) -> ok.

%%----------------------------------------------------------------------------

maybe_start(#exchange{name = #resource{name = XBin}} = X)->
    case shard(X) of
        true  -> 
            SPN = rabbit_stream_util:shards_per_node(X),
            RK  = rabbit_stream_util:routing_key(X),
            rabbit_misc:execute_mnesia_transaction(
              fun () ->
                  mnesia:write(?STREAM_TABLE,
                               #stream{name            = XBin,
                                       shards_per_node = SPN,
                                       routing_key     = RK},
                               write)
              end),
            rabbit_stream_util:rpc_call(ensure_sharded_queues, [X]),
            ok;
        false -> ok
    end.

shard(X) ->
    case stream_up() of 
        true -> rabbit_stream_util:shard(X);
        false -> false
    end.
    
stream_up() -> is_pid(whereis(rabbit_stream_app)).