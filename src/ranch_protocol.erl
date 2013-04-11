
%% 自定义行为模式
%% 自定义的协议处理器需要实现这个行为模式
-module(ranch_protocol).

%% 行为模式实现模块中在这个函数中启动新的进程处理客户端连接
%% 典型使用如下：
%%     Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
%%     {ok, Pid}.
%% conns sup 进程调用 start_link，启动工作进程

%% 关于 callback 关键字，参考 http://my.oschina.net/astute/blog/121837
%% 使用 callback 关键字替代 behaviour_info，极大的简化了代码，而且清晰易读
-callback start_link(
		Ref::any(),
		Socket::any(),
		Transport::module(),
		ProtocolOptions::any())
	-> {ok, ConnectionPid::pid()}.
