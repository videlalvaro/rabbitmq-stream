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
    Shard = {name(X), {rabbit_topic_shard, start_link, [X]},
            {permanent, 1}, ?MAX_WAIT, worker,
            [rabbit_topic_shard]},
    rabbit_log:info("starting shard: ~p on node ~p~n", [Shard, node()]),
    {ok, {{one_for_one, 1, 1}, [Shard]}}.

name(#exchange{name = #resource{name = XBin}}) -> 
    NodeBin = a2b(node()),
    <<"topic: ", XBin/binary, " - ", NodeBin/binary>>.

a2b(A) -> list_to_binary(atom_to_list(A)).