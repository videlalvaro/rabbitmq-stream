-module(rabbit_stream_parameters).

-behaviour(rabbit_runtime_parameter).
-behaviour(rabbit_policy_validator).

-include_lib("rabbit_common/include/rabbit.hrl").

-export([validate/4, notify/4, notify_clear/3]).
-export([register/0, validate_policy/1]).

-rabbit_boot_step({?MODULE,
                   [{description, "stream parameters"},
                    {mfa, {rabbit_stream_parameters, register, []}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).

%% $CTL set_parameter stream-definition my_stream '{"local-username": "guest", "shards-per-node": 4, "routing-key": "10000"}'
%% $CTL set_policy my-stream   "^stream\."   '{"stream-definition": "my_stream"}'

register() ->
    [rabbit_registry:register(Class, Name, ?MODULE) ||
        {Class, Name} <- [{runtime_parameter, <<"stream">>},
                          {runtime_parameter, <<"stream-definition">>},
                          {policy_validator,  <<"stream-definition">>}]],
    ok.

validate(_VHost, <<"stream">>, <<"shards-per-node">>, Term) ->
    validate_shards_per_node(<<"shards-per-node">>, Term);

validate(_VHost, <<"stream">>, <<"routing-key">>, Term) ->
    rabbit_parameter_validation:binary(<<"routing-key">>, Term);

validate(_VHost, <<"stream">>, <<"local-username">>, Term) ->
    rabbit_parameter_validation:binary(<<"local-username">>, Term);

validate(_VHost, <<"stream-definition">>, Name, Term) ->
    rabbit_parameter_validation:proplist(
       Name,
       [{<<"local-username">>, fun rabbit_parameter_validation:binary/2, mandatory},
        {<<"shards-per-node">>, fun validate_shards_per_node/2, optional},
        {<<"routing-key">>, fun rabbit_parameter_validation:binary/2, optional}],
      Term);

validate(_VHost, _Component, Name, _Term) ->
    {error, "name not recognised: ~p", [Name]}.

%% If the user wants to reduce the shards number, we can't
%% delete queues, but when adding new nodes, those nodes will
%% have the new parameter.
notify(VHost, <<"stream">>, <<"shards-per-node">>, _Term) ->
    rabbit_stream_shard:update_streams(VHost, shards_per_node),
    ok;

notify(VHost, <<"stream">>, <<"routing-key">>, _Term) ->
    rabbit_stream_shard:update_streams(VHost, all),
    ok;

notify(_VHost, <<"stream">>, _Name, _Term) ->
    ok;

%% Maybe increase shard number by declaring new queues 
%% in case shards-per-node increased.
%% We can't delete extra queues because the user might have messages on them.
%% We just ensure that there are SPN number of queues.
notify(VHost, <<"stream-definition">>, Name, _Term) ->
    rabbit_stream_shard:update_named_stream(VHost, Name),
    ok.

notify_clear(VHost, <<"stream">>, <<"shards-per-node">>) ->
    rabbit_stream_shard:update_streams(VHost, shards_per_node),
    ok;

notify_clear(VHost, <<"stream">>, <<"routing-key">>) ->
    rabbit_stream_shard:update_streams(VHost, all),
    ok;

%% A stream definition is gone. We can't remove queues so
%% we resort to defaults when declaring queues or while
%% intercepting channel methods.
%% 1) don't care about connection param changes. They will be
%%    used automatically next time we need to declare a queue.
%% 2) we need to bind the queues using the new routing key
%%    and unbind them from the old one.
notify_clear(VHost, <<"stream-definition">>, Name) ->
    rabbit_stream_shard:update_named_stream(VHost, Name),
    ok.

validate_shards_per_node(Name, Term) when is_number(Term) ->
    case Term >= 0 of
        true  ->
            ok;
        false ->
            {error, "~s should be greater than 0, actually was ~p", [Name, Term]}
    end;
validate_shards_per_node(Name, Term) ->
    {error, "~s should be number, actually was ~p", [Name, Term]}.

%%----------------------------------------------------------------------------

validate_policy([{<<"stream-definition">>, Value}])
  when is_binary(Value) ->
    ok;
validate_policy([{<<"stream-definition">>, Value}]) ->
    {error, "~p is not a valid stream name", [Value]}.
