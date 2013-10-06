-module(rabbit_topic_shard_util).

-include_lib("amqp_client/include/amqp_client.hrl").

%% real
-export([start_conn_ch/4, disposable_channel_call/2, disposable_channel_call/3,
         disposable_connection_call/3, disposable_connection_calls/3,
         ensure_connection_closed/1, handle_down/4]).

%% temp
-export([connection_error/5]).

-define(MAX_CONNECTION_CLOSE_TIMEOUT, 10000).

%%----------------------------------------------------------------------------

start_conn_ch(Fun, Params, XName = #resource{virtual_host = _VHost}, State) ->
    %% We trap exits so terminate/2 gets called. Note that this is not
    %% in init() since we need to cope with the link getting restarted
    %% during shutdown (when a broker federates with itself), which
    %% means we hang in topic_up() and the supervisor must force
    %% us to exit. We can therefore only trap exits when past that
    %% point. Bug 24372 may help us do something nicer.
    process_flag(trap_exit, true),
    %% TODO use proper params here: case open_monitor(local_params(Upstream, VHost)) of
    case open_monitor(Params) of
        {ok, Conn, Ch} ->
            try
                Fun(Conn, Ch)
            catch exit:E ->
                    %% terminate/2 will not get this, as we
                    %% have not put them in our state yet
                    ensure_connection_closed(Conn),
                    connection_error(local_start, E,
                                     Params, XName, State)
            end;
        E ->
            connection_error(local_start, E,
                             Params, XName, State)
    end.

open_monitor(Params) ->
    case open(Params) of
        {ok, Conn, Ch} -> erlang:monitor(process, Ch),
                          {ok, Conn, Ch};
        E              -> E
    end.

open(Params) ->
    case amqp_connection:start(Params) of
        {ok, Conn} -> case amqp_connection:open_channel(Conn) of
                          {ok, Ch} -> {ok, Conn, Ch};
                          E        -> catch amqp_connection:close(Conn),
                                      E
                      end;
        E -> E
    end.

ensure_channel_closed(Ch) -> catch amqp_channel:close(Ch).

ensure_connection_closed(Conn) ->
    catch amqp_connection:close(Conn, ?MAX_CONNECTION_CLOSE_TIMEOUT).

connection_error(local, basic_cancel, _Params, XName, State) ->
    rabbit_log:info("Topic ~s received 'basic.cancel'~n",
                    [rabbit_misc:rs(XName)]),
    {stop, {shutdown, restart}, State};

connection_error(local_start, E, _Params, XName, State) ->
    rabbit_log:warning("Topic ~s did not connect locally~n~p~n",
                       [rabbit_misc:rs(XName), E]),
    {stop, {shutdown, restart}, State}.

%%----------------------------------------------------------------------------

handle_down(Ch, Reason, Ch, State) ->
    {stop, {channel_down, Reason}, State}.

%%----------------------------------------------------------------------------

disposable_channel_call(Conn, Method) ->
    disposable_channel_call(Conn, Method, fun(_, _) -> ok end).

disposable_channel_call(Conn, Method, ErrFun) ->
    {ok, Ch} = amqp_connection:open_channel(Conn),
    try
        amqp_channel:call(Ch, Method)
    catch exit:{{shutdown, {server_initiated_close, Code, Text}}, _} ->
            ErrFun(Code, Text)
    after
        ensure_channel_closed(Ch)
    end.

disposable_connection_call(Params, Method, ErrFun) ->
    case open(Params) of
        {ok, Conn, Ch} ->
            try
                amqp_channel:call(Ch, Method)
            catch exit:{{shutdown, {connection_closing,
                                    {server_initiated_close, Code, Txt}}}, _} ->
                    ErrFun(Code, Txt)
            after
                ensure_connection_closed(Conn)
            end;
        E ->
            E
    end.

disposable_connection_calls(Params, Methods, ErrFun) ->
    case open(Params) of
        {ok, Conn, Ch} ->
            try
                [amqp_channel:call(Ch, Method) || Method <- Methods]
            catch exit:{{shutdown, {connection_closing,
                                    {server_initiated_close, Code, Txt}}}, _} ->
                    ErrFun(Code, Txt)
            after
                ensure_connection_closed(Conn)
            end;
        E ->
            E
    end.


% local_params(#upstream{trust_user_id = Trust}, VHost) ->
%     {ok, DefaultUser} = application:get_env(rabbit, default_user),
%     Username = rabbit_runtime_parameters:value(
%                  VHost, <<"federation">>, <<"local-username">>, DefaultUser),
%     case rabbit_access_control:check_user_login(Username, []) of
%         {ok, User0}        -> User = maybe_impersonator(Trust, User0),
%                               #amqp_params_direct{username     = User,
%                                                   virtual_host = VHost};
%         {refused, _M, _A}  -> exit({error, user_does_not_exist})
%     end.

% maybe_impersonator(Trust, User = #user{tags = Tags}) ->
%     case Trust andalso not lists:member(impersonator, Tags) of
%         true  -> User#user{tags = [impersonator | Tags]};
%         false -> User
%     end.
