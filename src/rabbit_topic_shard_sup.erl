-module(rabbit_topic_shard_sup).

-behaviour(supervisor2).

-include_lib("rabbit_common/include/rabbit.hrl").

%% Supervises the sharder.

-export([start_link/1]).
-export([init/1]).

start_link(X) ->
    supervisor2:start_link(?MODULE, X).

%%----------------------------------------------------------------------------

init(X) ->
    Shard = {X, {rabbit_topic_shard, start_link, [X]},
            {permanent, 1}, ?MAX_WAIT, worker,
            [rabbit_topic_shard]},
    {ok, {{one_for_one, 1, 1}, [Shard]}}.