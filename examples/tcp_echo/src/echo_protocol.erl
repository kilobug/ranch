
%% ranch_protocol 的实现模块
%% 必须实现 start_link 函数，必须调用 ranch:accept_ack，确保得到 client socket 的控制权
%% 如果此模块还要实现 gen_server 行为模式，需要特殊处理，参考 http://my.oschina.net/astute/blog/119250
%%
%% 应用逻辑的所在
%% 利用 ranch_tcp 模块提供的功能进行各种操作，接收数据，发送数据，发送文件
%% 这个 echo 的例子，对 ranch_tcp 的使用很不完整
-module(echo_protocol).
-export([start_link/4, init/4]).

start_link(Ref, Socket, Transport, Opts) ->
	Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
	{ok, Pid}.

init(Ref, Socket, Transport, _Opts = []) ->
  %% 必须调用 accept_ack，确保socket控制权
	ok = ranch:accept_ack(Ref),
	loop(Socket, Transport).

loop(Socket, Transport) ->
	case Transport:recv(Socket, 0, 5000) of
		{ok, Data} ->
			Transport:send(Socket, Data),
			loop(Socket, Transport);
		_ ->
			ok = Transport:close(Socket)
	end.
