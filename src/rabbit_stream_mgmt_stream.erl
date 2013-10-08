-module(rabbit_stream_mgmt_stream).

-export([init/1, to_json/2, resource_exists/2, content_types_provided/2,
         is_authorized/2]).

-include_lib("rabbitmq_management/include/rabbit_mgmt.hrl").
-include_lib("webmachine/include/webmachine.hrl").

%%--------------------------------------------------------------------

init(_Config) -> {ok, #context{}}.

content_types_provided(ReqData, Context) ->
   {[{"application/json", to_json}], ReqData, Context}.

resource_exists(ReqData, Context) ->
    {case exchange(ReqData) of
         not_found -> false;
         _         -> true
     end, ReqData, Context}.

to_json(ReqData, Context) ->
    rabbit_mgmt_util:reply(queues0(ReqData), ReqData, Context).

is_authorized(ReqData, Context) ->
    rabbit_mgmt_util:is_authorized_vhost(ReqData, Context).

%%--------------------------------------------------------------------

queues0(ReqData) ->
    case rabbit_mgmt_util:vhost(ReqData) of
        not_found -> [];
        VHost     -> 
            case exchange(ReqData) of
                {error, not_found} -> [];
                Exchange           -> maybe_filter(ReqData, Exchange, VHost)
            end
    end.

exchange(ReqData) ->
    case rabbit_mgmt_util:vhost(ReqData) of
        not_found -> not_found;
        VHost     -> exchange(VHost, id(ReqData))
    end.

exchange(VHost, XName) ->
    Name = rabbit_misc:r(VHost, exchange, XName),
    case rabbit_exchange:lookup(Name) of
        {ok, _X}            -> Name;
        {error, not_found}  -> not_found
    end.

id(ReqData) ->
    rabbit_mgmt_util:id(exchange, ReqData).

maybe_filter(ReqData, Exchange, VHost) ->
    case wrq:get_qs_value("node", ReqData) of
        "local"  -> 
            case rabbit_stream_util:queue_for_node(Exchange, VHost, node()) of
                {ok, Q} -> [Q];
                _       -> []
            end;
        "random" -> 
            random_queue(rabbit_stream_util:list_queues(Exchange, VHost));
        _ -> 
            rabbit_stream_util:list_queues(Exchange, VHost)
    end.
    
random_queue(Qs) ->
    case length(Qs) of
      Len when Len < 2 -> Qs;
      Len ->
        Rand = crypto:rand_uniform(1, Len + 1),
        [lists:nth(Rand, Qs)]
    end.