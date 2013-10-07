-module(rabbit_shard_exchange_decorator).

-rabbit_boot_step({?MODULE,
                   [{description, "shard exchange decorator"},
                    {mfa, {rabbit_registry, register,
                           [exchange_decorator, <<"shard">>, ?MODULE]}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).

-include_lib("amqp_client/include/amqp_client.hrl").

-behaviour(rabbit_exchange_decorator).

-export([description/0, serialise_events/1]).
-export([create/2, delete/3, policy_changed/2,
         add_binding/3, remove_bindings/3, route/2, active_for/1]).

%%----------------------------------------------------------------------------

description() ->
    [{description, <<"Shard exchange decorator">>}].

serialise_events(X) -> false.

create(transaction, _X) ->
    ok;
create(none, X) ->
    maybe_start(X).

delete(transaction, _X, _Bs) ->
    ok;
delete(none, X, _Bs) ->
    maybe_stop(X).

policy_changed(OldX, NewX) ->
    maybe_stop(OldX),
    maybe_start(NewX).

add_binding(_Tx, _X, _B) ->
    ok.

remove_bindings(_Tx, _X, _Bs) ->
    ok.

route(_, _) -> [].

active_for(X) ->
    case shard(X) of
        true  -> noroute;
        false -> none
    end.

%%----------------------------------------------------------------------------

shard(X) ->
    rabbit_topic_util:shard(X).

maybe_start(X = #exchange{name = XName})->
    case shard(X) of
        true  -> 
            rabbit_topic_util:rpc_call(X, start_child),
            ok;
        false -> ok
    end.

maybe_stop(X = #exchange{name = XName}) ->
    case shard(X) of
        true  -> 
            rabbit_topic_util:rpc_call(X, stop_child),
            ok;
        false -> ok
    end.