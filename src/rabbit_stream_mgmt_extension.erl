-module(rabbit_stream_mgmt_extension).

-behaviour(rabbit_mgmt_extension).

-export([dispatcher/0, web_ui/0]).

-include_lib("rabbitmq_management/include/rabbit_mgmt.hrl").
-include_lib("webmachine/include/webmachine.hrl").

dispatcher() -> 
    [{["stream-queues"],                  rabbit_stream_mgmt_streams, []},
     {["stream-queues", vhost],           rabbit_stream_mgmt_streams, []},
     {["stream-queues", vhost, exchange], rabbit_stream_mgmt_stream, []}
    ].

web_ui()     -> [{javascript, <<"stream.js">>}]. %% No UI for now.