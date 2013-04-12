
%% TCP transport API.
%% gen_tcp 的轻量级封装，实现了 Ranch transport API.
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

messages() -> {tcp, tcp_closed, tcp_error}.

%% 可用选项
%%     backlog 等待连接队列的长度，默认1024，nginx默认512
%%     ip 监听的网卡，默认所有网卡
%%     nodelay 开启 TCP_NODELAY，默认就开启
%%     port 端口号，默认0
-spec listen([{backlog, non_neg_integer()} | {ip, inet:ip_address()}
	| {nodelay, boolean()} | {port, inet:port_number()}])
	-> {ok, inet:socket()} | {error, atom()}.
listen(Opts) ->
	Opts2 = ranch:set_option_default(Opts, backlog, 1024),
	%% 第一个参数，设置端口号为0，表示操作系统随机选取一个可用的端口号，如果 Opts 中有 port 配置，优先级更高
	gen_tcp:listen(0, ranch:filter_options(Opts2, [backlog, ip, nodelay, port, raw],
		[binary, {active, false}, {packet, raw},
			{reuseaddr, true}, {nodelay, true}])).

-spec accept(inet:socket(), timeout())
	-> {ok, inet:socket()} | {error, closed | timeout | atom()}.
accept(LSocket, Timeout) ->
	gen_tcp:accept(LSocket, Timeout).

%% @todo Probably filter Opts?
-spec connect(inet:ip_address() | inet:hostname(),
	inet:port_number(), any())
	-> {ok, inet:socket()} | {error, atom()}.
connect(Host, Port, Opts) when is_integer(Port) ->
	gen_tcp:connect(Host, Port,
		Opts ++ [binary, {active, false}, {packet, raw}]).

-spec recv(inet:socket(), non_neg_integer(), timeout())
	-> {ok, any()} | {error, closed | atom()}.
recv(Socket, Length, Timeout) ->
	gen_tcp:recv(Socket, Length, Timeout).

-spec send(inet:socket(), iodata()) -> ok | {error, atom()}.
send(Socket, Packet) ->
	gen_tcp:send(Socket, Packet).

%% 通过 socket 发送文件
%% 使用TCP发送文件的可选方式。使用这个系统调用省去了用户空间的来回数据拷贝
-spec sendfile(inet:socket(), file:name())
	-> {ok, non_neg_integer()} | {error, atom()}.
sendfile(Socket, Filename) ->
	try file:sendfile(Filename, Socket) of
		Result -> Result
	catch
		error:{badmatch, {error, enotconn}} ->
      %% file:senfile/2 可能失败，抛出 {badmatch, {error, enotconn}}
      %% 因为 socket 连接不上的情况下，内部实现 prim_file:sendfile/10 失败
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
