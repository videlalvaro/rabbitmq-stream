-module(rabbit_topic_mgmt_extension).

-behaviour(rabbit_mgmt_extension).

-export([dispatcher/0, web_ui/0]).

-include_lib("rabbitmq_management/include/rabbit_mgmt.hrl").
-include_lib("webmachine/include/webmachine.hrl").

dispatcher() -> 
    [{["topic-queues"],                  rabbit_topic_mgmt_topics, []},
     {["topic-queues", vhost],           rabbit_topic_mgmt_topics, []},
     {["topic-queues", vhost, exchange], rabbit_topic_mgmt_topic, []}
    ].

web_ui()     -> [{javascript, <<"topic.js">>}]. %% No UI for now.