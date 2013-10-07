-module(rabbit_topic_shard_sup_sup).

-behaviour(supervisor2).

-include_lib("rabbit_common/include/rabbit.hrl").
-define(SUPERVISOR, ?MODULE).

%% Supervises the topic sharer process.

-export([start_link/0, start_child/1, stop_child/1]).
-export([init/1]).

%%----------------------------------------------------------------------------

start_link() ->
    supervisor2:start_link({local, ?SUPERVISOR}, ?MODULE, []).

%% this get called from the exchange during recovery
%% or exchange creation
start_child(X) ->
    case supervisor2:start_child(
           ?SUPERVISOR,
           {id(X), {rabbit_topic_shard_sup, start_link, [X]},
            transient, ?MAX_WAIT, supervisor,
            [rabbit_topic_shard_sup]}) of
        {ok, _Pid}                       -> ok;
        %% we received a broadcast to start the supervisor but it was running already.
        {error, {already_started, _Pid}} -> ok;
        %% A link returned {stop, gone}, the link_sup shut down, that's OK.
        {error, {shutdown, _}}           -> ok
    end.

%% this get called from the exchange deletion
stop_child(X) ->
    ok = supervisor2:terminate_child(?SUPERVISOR, id(X)),
    ok = supervisor2:delete_child(?SUPERVISOR, id(X)).

%%----------------------------------------------------------------------------

init([]) ->
    {ok, {{one_for_one, 3, 10}, []}}.

id(X = #exchange{}) -> X.
