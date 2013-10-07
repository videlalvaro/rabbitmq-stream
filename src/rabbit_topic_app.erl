-module(rabbit_topic_app).

-behaviour(application).
-export([start/2, stop/1]).

-export([maybe_shard_exchanges/0]).

%% Dummy supervisor - see Ulf Wiger's comment at
%% http://erlang.2086793.n4.nabble.com/initializing-library-applications-without-processes-td2094473.html

%% All of our actual server processes are supervised by
%% rabbit_federation_sup, which is started by a rabbit_boot_step
%% (since it needs to start up before queue / exchange recovery, so it
%% can't be part of our application).
%%
%% However, we still need an application behaviour since we need to
%% know when our application has started since then the Erlang client
%% will have started and we can therefore start our links going. Since
%% the application behaviour needs a tree of processes to supervise,
%% this is it...
-behaviour(supervisor).
-export([init/1]).

-rabbit_boot_step({rabbit_topic_maybe_share,
                   [{description, "rabbit topic maybe shard"},
                    {mfa,         {?MODULE, maybe_shard_exchanges, []}},
                    {requires,    recovery}]}).

start(_Type, _StartArgs) ->
    rabbit_log:info("starting rabbit_topic_app on node ~p~n", [node()]),
    rabbit_topic_shard:go(),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop(_State) ->
    ok.
%%----------------------------------------------------------------------------

init([]) -> {ok, {{one_for_one, 3, 10}, []}}.

maybe_shard_exchanges() ->
    rabbit_topic_util:maybe_shard_exchanges(<<"/">>),
    ok.