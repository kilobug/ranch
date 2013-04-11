
%% Ranch API
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
%%
%% 如果 Ranch 作为单独的应用启动，自己写的应用可以使用多次调用 ranch:start_listener，
%% 只是必须要传入不同的 Ref 和 port。
%% 每个ranch应用，ranch_server 只有一个;
%% ranch_listener_sup 每一个启动的应用会有一个，底下还有acceptors池，conns sup进程
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
      %% ranch_listener_sup 是一个监督树结构
			Res = supervisor:start_child(ranch_sup, child_spec(Ref, NbAcceptors,
					Transport, TransOpts, Protocol, ProtoOpts)),
      %% ranch 可以从已经存在的 listen socket 获取连接
      %% 需要在传输层选项中配置 socket 参数；参考 ranch user guide 2 Listeners
			Socket = proplists:get_value(socket, TransOpts),
			case Res of
				{ok, Pid} when Socket =/= undefined ->
					%% ranch_listener_sup 一共有两个子进程，ranch_acceptors_sup 和 ranch_conns_sup
					%% 把 listen socket 的控制进程设置为 ranch_acceptors_sup 进程
					%% 只要 ranch_acceptors_sup 进程不死，listen socket就不会关闭；
					%% 如果进程死掉了，那么我们不能恢复，因为我们不知道如何再次打开
					Children = supervisor:which_children(Pid), %% 获取子进程列表
					{_, AcceptorsSup, _, _}
						= lists:keyfind(ranch_acceptors_sup, 1, Children),
          %% 由于 erlang 的 bug，改变 ssl listen socket 的控制进程会 crash，所以这个地方使用 catch；
          %% bug 会在 R16 中修复。
					catch Transport:controlling_process(Socket, AcceptorsSup);
				_ ->
					ok
			end,
			Res
	end.

%% 停止应用 Ref 的监听器
%% 关闭 ranch_listener_sup 会导致当前所有正在运行的连接关闭
-spec stop_listener(any()) -> ok | {error, not_found}.
stop_listener(Ref) ->
  %% {ranch_listener_sup, Ref} 为 子进程 ID
  %% 停止子进程
	case supervisor:terminate_child(ranch_sup, {ranch_listener_sup, Ref}) of
		ok ->
      %% 删除子进程规范，删掉的是整棵树
			_ = supervisor:delete_child(ranch_sup, {ranch_listener_sup, Ref}),
			ranch_server:cleanup_listener_opts(Ref);
		{error, Reason} ->
			{error, Reason}
	end.

%% 生成适合嵌入应用的子进程规范
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

%% 确保socket使用前，控制权已经转移给工作进程
%% 如果不做这样的一步消息传递来同步，工作进程可能会提前执行到 recv 代码处
-spec accept_ack(any()) -> ok.
accept_ack(Ref) ->
	receive {shoot, Ref} -> ok end.

%% 从池中移除调用进程的连接
%% 系统中可能存在一些长期存活的连接，但是这些连接大部分时候并没有事可做，
%% 可能在等待客户端的数据；这个时候，工作进程就应该调用这个函数，将当前连接数减一，
%% 因为这个连接在限制并发数时不应该被统计在内。
%% 这个设计还是很精妙的
%% 注意：需要在 ranch_protocol 实现中手动调用
-spec remove_connection(any()) -> ok.
remove_connection(Ref) ->
	ConnsSup = ranch_server:get_connections_sup(Ref),
	ConnsSup ! {remove_connection, Ref},
	ok.

%% 查询 listen socket 监听端口
-spec get_port(any()) -> inet:port_number().
get_port(Ref) ->
	ranch_server:get_port(Ref).

%% 查询设定的最大连接数
-spec get_max_connections(any()) -> max_conns().
get_max_connections(Ref) ->
	ranch_server:get_max_connections(Ref).

%% 设置最大连接数
%% ranch:set_max_connections  -->  ranch_server:set_max_connections -->  给 conns sup 进程发消息，{set_max_conns, MaxConns}
%% ranch 模块提供 API，给外部应用使用； ranch_server 保存所有应用的配置信息；conns sup 进程才是控制连接并发数的最终进程
%% 设计还是挺巧妙的
-spec set_max_connections(any(), max_conns()) -> ok.
set_max_connections(Ref, MaxConnections) ->
	ranch_server:set_max_connections(Ref, MaxConnections).

%% 查询应用的协议配置选项值
-spec get_protocol_options(any()) -> any().
get_protocol_options(Ref) ->
	ranch_server:get_protocol_options(Ref).

%% 配置协议选项，最终这些选项会被 ranch_protocol 的实现使用，也就是应用层使用
%% 这个更新或配置只影响新获取的连接和工作进程，不影响已经打开的连接。
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
