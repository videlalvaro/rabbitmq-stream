-module(rabbit_topic_parameters).

-behaviour(rabbit_runtime_parameter).
-behaviour(rabbit_policy_validator).

-include_lib("rabbit_common/include/rabbit.hrl").

-export([validate/4, notify/4, notify_clear/3]).
-export([register/0, validate_policy/1]).

-rabbit_boot_step({?MODULE,
                   [{description, "topic parameters"},
                    {mfa, {rabbit_topic_parameters, register, []}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).

register() ->
    rabbit_registry:register(runtime_parameter, <<"topic">>, ?MODULE),
    rabbit_registry:register(policy_validator,  <<"topic">>, ?MODULE),
    ok.

validate(_VHost, <<"topic">>, <<"topic-name">>, Term) ->
    rabbit_parameter_validation:binary(<<"topic-name">>, Term);
    % rabbit_parameter_validation:proplist([{<<"topic-name">>, fun rabbit_parameter_validation:binary/2, mandatory}], Term);

validate(_VHost, _Component, Name, _Term) ->
    {error, "name not recognised: ~p", [Name]}.

%% TODO update topic name.
notify(_VHost, <<"topic">>, <<"topic-name">>, Term) ->
    io:format("notify Term: ~p~n", [Term]),
    ok.

%% TODO remove policy and delete queues.
notify_clear(_VHost, <<"topic">>, Name) ->
    io:format("notify_clear Name: ~p~n", [Name]),
    ok.
    
validate_policy([{<<"topic">>, Value}])
  when is_binary(Value) ->
    ok;
validate_policy([{<<"topic">>, Value}]) ->
    {error, "~p is not a valid topic name", [Value]}.