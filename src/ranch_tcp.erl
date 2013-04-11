
%% TCP transport API.
%% gen_tcp 的轻量级封装，实现了 Ranch transport API.
%%
-module(ranch_tcp).
-behaviour(ranch_transport).

-export([name/0]).
-export([messages/0]).
-export([listen/1]).
-export([accept/2]).
-export([connect/3]).
-export([recv/3]).
-export([send/2]).
-export([sendfile/2]).
-export([setopts/2]).
-export([controlling_process/2]).
-export([peername/1]).
-export([sockname/1]).
-export([close/1]).

%% 传输层的名字，tcp.
name() -> tcp.

%% Atoms used to identify messages in {active, once | true} mode.
messages() -> {tcp, tcp_closed, tcp_error}.

%% @doc Listen for connections on the given port number.
%%
%% Calling this function returns a listening socket that can then
%% be passed to accept/2 to accept connections.
%%
%% The available options are:
%% <dl>
%%  <dt>backlog</dt><dd>Maximum length of the pending connections queue.
%%   Defaults to 1024.</dd>
%%  <dt>ip</dt><dd>Interface to listen on. Listen on all interfaces
%%   by default.</dd>
%%  <dt>nodelay</dt><dd>Optional. Enable TCP_NODELAY. Enabled by default.</dd>
%%  <dt>port</dt><dd>TCP port number to open. Defaults to 0 (see below).</dd>
%% </dl>
%%
%% You can listen to a random port by setting the port option to 0.
%% It is then possible to retrieve this port number by calling
%% sockname/1 on the listening socket. If you are using Ranch's
%% listener API, then this port number can obtained through
%% ranch:get_port/1 instead.
%%
%% @see gen_tcp:listen/2
-spec listen([{backlog, non_neg_integer()} | {ip, inet:ip_address()}
	| {nodelay, boolean()} | {port, inet:port_number()}])
	-> {ok, inet:socket()} | {error, atom()}.
listen(Opts) ->
	Opts2 = ranch:set_option_default(Opts, backlog, 1024),
	%% 第一个参数，设置端口号为0，表示操作系统随机选取一个可用的端口号，如果 Opts 中有 port 配置，优先级更高
	gen_tcp:listen(0, ranch:filter_options(Opts2, [backlog, ip, nodelay, port, raw],
		[binary, {active, false}, {packet, raw},
			{reuseaddr, true}, {nodelay, true}])).

%% @doc Accept connections with the given listening socket.
%% @see gen_tcp:accept/2
-spec accept(inet:socket(), timeout())
	-> {ok, inet:socket()} | {error, closed | timeout | atom()}.
accept(LSocket, Timeout) ->
	gen_tcp:accept(LSocket, Timeout).

%% @private Experimental. Open a connection to the given host and port number.
%% @see gen_tcp:connect/3
%% @todo Probably filter Opts?
-spec connect(inet:ip_address() | inet:hostname(),
	inet:port_number(), any())
	-> {ok, inet:socket()} | {error, atom()}.
connect(Host, Port, Opts) when is_integer(Port) ->
	gen_tcp:connect(Host, Port,
		Opts ++ [binary, {active, false}, {packet, raw}]).

%% @doc Receive data from a socket in passive mode.
%% @see gen_tcp:recv/3
-spec recv(inet:socket(), non_neg_integer(), timeout())
	-> {ok, any()} | {error, closed | atom()}.
recv(Socket, Length, Timeout) ->
	gen_tcp:recv(Socket, Length, Timeout).

%% @doc Send data on a socket.
%% @see gen_tcp:send/2
-spec send(inet:socket(), iodata()) -> ok | {error, atom()}.
send(Socket, Packet) ->
	gen_tcp:send(Socket, Packet).

%% @doc Send a file on a socket.
%%
%% This is the optimal way to send files using TCP. It uses a syscall
%% which means there is no context switch between opening the file
%% and writing its contents on the socket.
%%
%% @see file:sendfile/2
-spec sendfile(inet:socket(), file:name())
	-> {ok, non_neg_integer()} | {error, atom()}.
sendfile(Socket, Filename) ->
	try file:sendfile(Filename, Socket) of
		Result -> Result
	catch
		error:{badmatch, {error, enotconn}} ->
			%% file:sendfile/2 might fail by throwing a {badmatch, {error, enotconn}}
			%% this is because its internal implementation fails with a badmatch in
			%% prim_file:sendfile/10 if the socket is not connected.
			{error, closed}
	end.

%% 设置socket参数
%% 需要过滤选项?
-spec setopts(inet:socket(), list()) -> ok | {error, atom()}.
setopts(Socket, Opts) ->
	inet:setopts(Socket, Opts).

%% 设置 socket 控制进程
-spec controlling_process(inet:socket(), pid())
	-> ok | {error, closed | not_owner | atom()}.
controlling_process(Socket, Pid) ->
	gen_tcp:controlling_process(Socket, Pid).

%% 返回连接另一端的ip地址和端口
-spec peername(inet:socket())
	-> {ok, {inet:ip_address(), inet:port_number()}} | {error, atom()}.
peername(Socket) ->
	inet:peername(Socket).

%% 返回连接的本地 ip 地址和 port.
-spec sockname(inet:socket())
	-> {ok, {inet:ip_address(), inet:port_number()}} | {error, atom()}.
sockname(Socket) ->
	inet:sockname(Socket).

%% 关闭 socket.
-spec close(inet:socket()) -> ok.
close(Socket) ->
	gen_tcp:close(Socket).
