
%% 传输层的行为模式定义
%% 为 ranch_tcp 和 ranch_ssl 提供API
-module(ranch_transport).

-type socket() :: any().
-type opts() :: any().

%% 传输层的名字
-callback name() -> atom().

%% 在 {active, once | true} 模式中，用来识别消息的原子
-callback messages() -> {OK::atom(), Closed::atom(), Error::atom()}.

%% 在指定端口上监听连接
%% 调用这个函数会返回 listen socket，用来作为 accept/2 的参数
%% 不同的传输层会有不同的选项
%% 设置端口为0，表示监听在一个随机端口
%% 可以使用 sockname/1 查询监听的端口号
%% 可以使用 ranch 提供的 API ranch:get_port/1 来查询端口号
-callback listen(opts()) -> {ok, socket()} | {error, atom()}.

%% 接收连接
-callback accept(socket(), timeout())
	-> {ok, socket()} | {error, closed | timeout | atom() | tuple()}.

%% 实验性质
%% 连接到远程的IP地址和端口号
-callback connect(string(), inet:port_number(), opts())
	-> {ok, socket()} | {error, atom()}.

%% 被动模式下接收数据
-callback recv(socket(), non_neg_integer(), timeout())
	-> {ok, any()} | {error, closed | timeout | atom()}.

%% 发送数据
-callback send(socket(), iodata()) -> ok | {error, atom()}.

%% 设置参数
-callback setopts(socket(), opts()) -> ok | {error, atom()}.

%% 设置 socket 控制进程
%% 必须从当前控制socket的进程调用，否则 {error, not_owner} 错误会返回
-callback controlling_process(socket(), pid())
	-> ok | {error, closed | not_owner | atom()}.

%% 返回连接另一端的IP地址和端口号
-callback peername(socket())
	-> {ok, {inet:ip_address(), inet:port_number()}} | {error, atom()}.

%% 返回本地地址和端口号
-callback sockname(socket())
	-> {ok, {inet:ip_address(), inet:port_number()}} | {error, atom()}.

%% 关闭 socket
-callback close(socket()) -> ok.
