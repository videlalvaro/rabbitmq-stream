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

register() ->
    rabbit_registry:register(runtime_parameter, <<"stream">>, ?MODULE),
    rabbit_registry:register(policy_validator,  <<"stream">>, ?MODULE),
    ok.

validate(_VHost, <<"stream">>, <<"stream-name">>, Term) ->
    rabbit_parameter_validation:binary(<<"stream-name">>, Term);
    % rabbit_parameter_validation:proplist([{<<"stream-name">>, fun rabbit_parameter_validation:binary/2, mandatory}], Term);

validate(_VHost, _Component, Name, _Term) ->
    {error, "name not recognised: ~p", [Name]}.

%% TODO update stream name.
notify(_VHost, <<"stream">>, <<"stream-name">>, Term) ->
    io:format("notify Term: ~p~n", [Term]),
    ok.

%% TODO remove policy and delete queues.
notify_clear(_VHost, <<"stream">>, Name) ->
    io:format("notify_clear Name: ~p~n", [Name]),
    ok.
    
validate_policy([{<<"stream">>, Value}])
  when is_binary(Value) ->
    ok;
validate_policy([{<<"stream">>, Value}]) ->
    {error, "~p is not a valid stream name", [Value]}.