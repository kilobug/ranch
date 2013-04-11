
%% 连接获取进程的监督者
%% 底下有 NbAcceptors 个子进程 ranch_acceptor
-module(ranch_acceptors_sup).
-behaviour(supervisor).

%% API.
-export([start_link/4]).

%% supervisor.
-export([init/1]).

%% API.

%% 参数：(tcp_echo, 1, ranch_tcp, [{port, 5555}])
-spec start_link(any(), non_neg_integer(), module(), any())
	-> {ok, pid()}.
start_link(Ref, NbAcceptors, Transport, TransOpts) ->
	supervisor:start_link(?MODULE, [Ref, NbAcceptors, Transport, TransOpts]).

%% supervisor.

%% 参数：(tcp_echo, 1, ranch_tcp, [{port, 5555}])
init([Ref, NbAcceptors, Transport, TransOpts]) ->
	ConnsSup = ranch_server:get_connections_sup(Ref),
  %% LSocket -> Listen Socket
  %% 如果是要监听已经存在的 listen socket，需要获取到端口号，通过调用 sockname
  %% listen socket 的控制进程就是 ranch_acceptors_sup 进程
	LSocket = case proplists:get_value(socket, TransOpts) of
		undefined ->
			{ok, Socket} = Transport:listen(TransOpts),
			Socket;
		Socket ->
			Socket
	end,
	{ok, {_, Port}} = Transport:sockname(LSocket),
	ranch_server:set_port(Ref, Port),
  %% acceptor 池配置的多大，就有多少 ranch_acceptor
	Procs = [
		{{acceptor, self(), N}, {ranch_acceptor, start_link, [
			LSocket, Transport, ConnsSup
		]}, permanent, brutal_kill, worker, []}
			|| N <- lists:seq(1, NbAcceptors)],
	{ok, {{one_for_one, 10, 10}, Procs}}.
