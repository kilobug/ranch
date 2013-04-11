
%% 连接获取进程
-module(ranch_acceptor).

%% API.
-export([start_link/3]).

%% Internal.
-export([loop/3]).

%% API.

-spec start_link(inet:socket(), module(), pid())
	-> {ok, pid()}.
start_link(LSocket, Transport, ConnsSup) ->
	Pid = spawn_link(?MODULE, loop, [LSocket, Transport, ConnsSup]),
	{ok, Pid}.

%% Internal.

-spec loop(inet:socket(), module(), pid()) -> no_return().
loop(LSocket, Transport, ConnsSup) ->
	_ = case Transport:accept(LSocket, infinity) of
		{ok, CSocket} ->
			Transport:controlling_process(CSocket, ConnsSup),
			%% 这一步是同步的调用，需要等待 conns sup 进程 生成 client socket 操作进程，返回 self() 为止
			ranch_conns_sup:start_protocol(ConnsSup, CSocket);
		%% listene scoket 关闭时，acceptor 进程由于匹配失败崩溃
		{error, Reason} when Reason =/= closed ->
			ok
	end,
	?MODULE:loop(LSocket, Transport, ConnsSup).
