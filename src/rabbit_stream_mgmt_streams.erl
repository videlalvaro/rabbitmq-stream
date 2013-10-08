-module(rabbit_stream_mgmt_streams).

-export([init/1, to_json/2, resource_exists/2, content_types_provided/2,
         is_authorized/2]).

-include_lib("rabbitmq_management/include/rabbit_mgmt.hrl").
-include_lib("webmachine/include/webmachine.hrl").

%%--------------------------------------------------------------------

init(_Config) -> {ok, #context{}}.

content_types_provided(ReqData, Context) ->
   {[{"application/json", to_json}], ReqData, Context}.

resource_exists(ReqData, Context) ->
    {case queues0(ReqData) of
         vhost_not_found -> false;
         _               -> true
     end, ReqData, Context}.

to_json(ReqData, Context) ->
    rabbit_mgmt_util:reply(queues0(ReqData), ReqData, Context).

is_authorized(ReqData, Context) ->
    rabbit_mgmt_util:is_authorized_vhost(ReqData, Context).

%%--------------------------------------------------------------------

queues0(ReqData) ->
    rabbit_mgmt_util:all_or_one_vhost(ReqData, fun rabbit_stream_util:list_queues_on_vhost/1).