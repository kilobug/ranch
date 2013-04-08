
%% @doc Ranch API to start and stop listeners.
-module(ranch).

-export([start_listener/6]).
-export([stop_listener/1]).
-export([child_spec/6]).
-export([accept_ack/1]).
-export([remove_connection/1]).
-export([get_port/1]).
-export([get_max_connections/1]).
-export([set_max_connections/2]).
-export([get_protocol_options/1]).
-export([set_protocol_options/2]).
-export([filter_options/3]).
-export([set_option_default/3]).
-export([require/1]).

-type max_conns() :: non_neg_integer() | infinity.
-export_type([max_conns/0]).


%% @doc 给定传输层transport和协议protocol，启动监听器listener
%% 监听器是含有NbAcceptors个acceptor的池
%% Acceptor在给定的Transport上接受连接，转发连接到给定的协议处理器
%% TransOpts是传输层的设置选项，ProtoOpts是协议选项。
%% 监听器listener监督所有的acceptor和连接进程
%% 为了提高性能，推荐设置足够大的acceptor数目。确切的数字依赖于硬件，协议和期望的并发连接的数目。
%% 传输Transprot选项max_connections允许定义并发连接的最大数目，默认是1024.
%% transport出错，会返回`{error, badarg}`
%% ranch:start_listener(tcp_echo, 1, ranch_tcp, [{port, 5555}], echo_protocol, [])
%% Ref 指的是应用
-spec start_listener(any(), non_neg_integer(), module(), any(), module(), any())
	-> {ok, pid()} | {error, badarg}.
start_listener(Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts)
		when is_integer(NbAcceptors) andalso is_atom(Transport)
		andalso is_atom(Protocol) ->
	_ = code:ensure_loaded(Transport),
	case erlang:function_exported(Transport, name, 0) of
		false ->
			{error, badarg};
		true ->
      %% 给 ranch_sup 添加一个 ranch_listener_sup 子进程（之前还有一个 ranch_server 子进程）
      %% ranch_listener_sup 是一个监督者
			Res = supervisor:start_child(ranch_sup, child_spec(Ref, NbAcceptors,
					Transport, TransOpts, Protocol, ProtoOpts)),
			Socket = proplists:get_value(socket, TransOpts),
			case Res of
				{ok, Pid} when Socket =/= undefined ->
					%% Give ownership of the socket to ranch_acceptors_sup
					%% to make sure the socket stays open as long as the
					%% listener is alive. If the socket closes however there
					%% will be no way to recover because we don't know how
					%% to open it again.
          %% 获取 id 为 ranch_acceptors_sup 的子进程
          %% 把 socket 控制进程设置为获取的子进程 ？？？
					Children = supervisor:which_children(Pid),
					{_, AcceptorsSup, _, _}
						= lists:keyfind(ranch_acceptors_sup, 1, Children),
					%%% Note: the catch is here because SSL crashes when you change
					%%% the controlling process of a listen socket because of a bug.
					%%% The bug will be fixed in R16.
					catch Transport:controlling_process(Socket, AcceptorsSup);
				_ ->
					ok
			end,
			Res
	end.

%% @doc Stop a listener identified by <em>Ref</em>.
%%
%% Note that stopping the listener will close all currently running
%% connections abruptly.
-spec stop_listener(any()) -> ok | {error, not_found}.
stop_listener(Ref) ->
	case supervisor:terminate_child(ranch_sup, {ranch_listener_sup, Ref}) of
		ok ->
			_ = supervisor:delete_child(ranch_sup, {ranch_listener_sup, Ref}),
			ranch_server:cleanup_listener_opts(Ref);
		{error, Reason} ->
			{error, Reason}
	end.

%% @doc 生成适合嵌入应用的子进程规范
%% 如果要在应用中嵌入ranch，可以使用这个函数来生成监督者使用的子进程规范。参数和
%% start_listener相同，但不会把listener挂街道ranch内部的监督树，只是返回子进程规范。
%% 传入参数：(tcp_echo, 1, ranch_tcp, [{port, 5555}], echo_protocol, [])
-spec child_spec(any(), non_neg_integer(), module(), any(), module(), any())
	-> supervisor:child_spec().
child_spec(Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts)
		when is_integer(NbAcceptors) andalso is_atom(Transport)
		andalso is_atom(Protocol) ->
	{{ranch_listener_sup, Ref}, {ranch_listener_sup, start_link, [
		Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts
	]}, permanent, 5000, supervisor, [ranch_listener_sup]}.

%% @doc Acknowledge the accepted connection.
%%
%% Effectively used to make sure the socket control has been given to
%% the protocol process before starting to use it.
-spec accept_ack(any()) -> ok.
accept_ack(Ref) ->
	receive {shoot, Ref} -> ok end.

%% @doc Remove the calling process' connection from the pool.
%%
%% Useful if you have long-lived connections that aren't taking up
%% resources and shouldn't be counted in the limited number of running
%% connections.
-spec remove_connection(any()) -> ok.
remove_connection(Ref) ->
	ConnsSup = ranch_server:get_connections_sup(Ref),
	ConnsSup ! {remove_connection, Ref},
	ok.

%% @doc Return the listener's port.
-spec get_port(any()) -> inet:port_number().
get_port(Ref) ->
	ranch_server:get_port(Ref).

%% @doc Return the max number of connections allowed concurrently.
-spec get_max_connections(any()) -> max_conns().
get_max_connections(Ref) ->
	ranch_server:get_max_connections(Ref).

%% @doc Set the max number of connections allowed concurrently.
-spec set_max_connections(any(), max_conns()) -> ok.
set_max_connections(Ref, MaxConnections) ->
	ranch_server:set_max_connections(Ref, MaxConnections).

%% @doc Return the current protocol options for the given listener.
-spec get_protocol_options(any()) -> any().
get_protocol_options(Ref) ->
	ranch_server:get_protocol_options(Ref).

%% @doc Upgrade the protocol options for the given listener.
%%
%% The upgrade takes place at the acceptor level, meaning that only the
%% newly accepted connections receive the new protocol options. This has
%% no effect on the currently opened connections.
-spec set_protocol_options(any(), any()) -> ok.
set_protocol_options(Ref, Opts) ->
	ranch_server:set_protocol_options(Ref, Opts).

%% 过滤选项列表，移除不希望的值，实际就是选项参数校验
%% 函数接收选项列表，允许key的列表，和累加器
%% 累加器用来设置默认的不可被覆盖的选项 [binary, {active, false}, {packet, raw}, {reuseaddr, true}, {nodelay, true}]
%% 参数：(Opts2, [backlog, ip, nodelay, port, raw], [binary, {active, false}, {packet, raw}, {reuseaddr, true}, {nodelay, true}])
-spec filter_options([{atom(), any()}], [atom()], Acc)
	-> Acc when Acc :: [any()].
filter_options([], _, Acc) ->
	Acc;
filter_options([Opt = {Key, _}|Tail], AllowedKeys, Acc) ->
	case lists:member(Key, AllowedKeys) of
		true -> filter_options(Tail, AllowedKeys, [Opt|Acc]);
		false -> filter_options(Tail, AllowedKeys, Acc)
	end;
filter_options([Opt = {raw, _, _, _}|Tail], AllowedKeys, Acc) ->
	case lists:member(raw, AllowedKeys) of
		true -> filter_options(Tail, AllowedKeys, [Opt|Acc]);
		false -> filter_options(Tail, AllowedKeys, Acc)
	end.

%% 向选项列表中添加选项，前提是该选项之前没有设置
-spec set_option_default(Opts, atom(), any())
	-> Opts when Opts :: [{atom(), any()}].
set_option_default(Opts, Key, Value) ->
	case lists:keymember(Key, 1, Opts) of
		true -> Opts;
		false -> [{Key, Value}|Opts]
	end.

%% @doc Start the given applications if they were not already started.
-spec require(list(module())) -> ok.
require([]) ->
	ok;
require([App|Tail]) ->
	case application:start(App) of
		ok -> ok;
		{error, {already_started, App}} -> ok
	end,
	require(Tail).
