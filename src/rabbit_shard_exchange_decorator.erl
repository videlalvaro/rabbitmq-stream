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

serialise_events(X) -> shard(X).

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

%% only shard consistent hash exchanges.
shard(X = #exchange{type = 'x-consistent-hash'}) ->
    case rabbit_policy:get(<<"topic">>, X) of
        undefined -> false;
        _         -> true
    end;

shard(X) ->
    io:format("tried to shard exchange: ~p~n", [X]),
    false.

maybe_start(X = #exchange{name = XName})->
    io:format("maybe_start: ~p~n", [XName]),
    case shard(X) of
        true  -> 
            ok = rabbit_topic_shard_sup_sup:start_child(X),
            ok;
        false -> ok
    end.

maybe_stop(X = #exchange{name = XName}) ->
    io:format("maybe_stop: ~p~n", [XName]),
    case shard(X) of
        true  -> ok = rabbit_topic_shard_sup_sup:stop_child(X);
        false -> ok
    end.
