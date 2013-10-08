-module(rabbit_topic_sup).

-behaviour(supervisor).

%% Supervises everything. There is just one of these.

-include_lib("rabbit_common/include/rabbit.hrl").
-define(SUPERVISOR, ?MODULE).

-export([start_link/0]).

-export([init/1]).

%% This supervisor needs to be part of the rabbit application since
%% a) it needs to be in place when exchange recovery takes place
%% b) it needs to go up and down with rabbit

% -rabbit_boot_step({rabbit_topic_supervisor,
%                    [{description, "rabbit topic shards"},
%                     {mfa,         {rabbit_sup, start_child, [?MODULE]}},
%                     {requires,    kernel_ready},
%                     {enables,     rabbit_shard_exchange_decorator}]}).

%%----------------------------------------------------------------------------

start_link() ->
    supervisor:start_link({local, ?SUPERVISOR}, ?MODULE, []).

%%----------------------------------------------------------------------------

init([]) ->
    TopicShardSupSup = {topic_shard_sup_sup,
                   {rabbit_topic_shard_sup_sup, start_link, []},
                   transient, ?MAX_WAIT, supervisor,
                   [rabbit_topic_shard_sup_sup]},
    {ok, {{one_for_one, 3, 10}, [TopicShardSupSup]}}.
