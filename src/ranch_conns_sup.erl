
%% Make sure to never reload this module outside a release upgrade,
%% as calling l(ranch_conns_sup) twice will kill the process and all
%% the currently open connections.
%% ranch_conns_sup 是一个监督者，但并没有实现 supervisor 模式，
-module(ranch_conns_sup).

%% API.
-export([start_link/3]).
-export([start_protocol/2]).
-export([active_connections/1]).

%% Supervisor internals.
-export([init/4]).
-export([system_continue/3]).
-export([system_terminate/4]).
-export([system_code_change/4]).

-record(state, {
	parent = undefined :: pid(),
	ref :: any(),
	transport = undefined :: module(),
	protocol = undefined :: module(),
	opts :: any(),
	max_conns = undefined :: non_neg_integer() | infinity
}).

%% API.

%% 参数：[tcp_echo, ranch_tcp, echo_protocol]
-spec start_link(any(), module(), module()) -> {ok, pid()}.
start_link(Ref, Transport, Protocol) ->
	proc_lib:start_link(?MODULE, init, [self(), Ref, Transport, Protocol]).

%% We can safely assume we are on the same node as the supervisor.
%%
%% We can also safely avoid having a monitor and a timeout here
%% because only three things can happen:
%%  *  The supervisor died; rest_for_one strategy killed all acceptors
%%     so this very calling process is going to di--
%%  *  There's too many connections, the supervisor will resume the
%%     acceptor only when we get below the limit again.
%%  *  The supervisor is overloaded, there's either too many acceptors
%%     or the max_connections limit is too large. It's better if we
%%     don't keep accepting connections because this leaves
%%     more room for the situation to be resolved.
%%
%% We do not need the reply, we only need the ok from the supervisor
%% to continue. The supervisor sends its own pid when the acceptor can
%% continue.
%% acceptor 和 conns sup 在同一节点上
%% acceptor 进程调用的这个函数
%% 函数中的发送和接受语句没有超时和监控的问题
%% 如果 ranch_acceptors_sup 崩溃，那么所有的 acceptor 进程都会 die
%% 连接过多，conns sup 会
-spec start_protocol(pid(), inet:socket()) -> ok.
start_protocol(SupPid, Socket) ->
	SupPid ! {?MODULE, start_protocol, self(), Socket},
	receive SupPid -> ok end.

%% We can't make the above assumptions here. This function might be
%% called from anywhere.
-spec active_connections(pid()) -> non_neg_integer().
active_connections(SupPid) ->
	Tag = erlang:monitor(process, SupPid),
	erlang:send(SupPid, {?MODULE, active_connections, self(), Tag},
		[noconnect]),
	receive
		{Tag, Ret} ->
			erlang:demonitor(Tag, [flush]),
			Ret;
		{'DOWN', Tag, _, _, noconnection} ->
			exit({nodedown, node(SupPid)});
		{'DOWN', Tag, _, _, Reason} ->
			exit(Reason)
	after 5000 ->
		erlang:demonitor(Tag, [flush]),
		exit(timeout)
	end.

%% Supervisor internals.

%% 让 ranch_conns_sup 进程成为 master 进程
%% proc_lib:start_link 和 proc_lib:init_ack 的成对使用
%%
-spec init(pid(), any(), module(), module()) -> no_return().
init(Parent, Ref, Transport, Protocol) ->
	process_flag(trap_exit, true),
	ok = ranch_server:set_connections_sup(Ref, self()),
	MaxConns = ranch_server:get_max_connections(Ref),
	Opts = ranch_server:get_protocol_options(Ref),
	ok = proc_lib:init_ack(Parent, {ok, self()}),
	loop(#state{parent=Parent, ref=Ref, transport=Transport,
		protocol=Protocol, opts=Opts, max_conns=MaxConns}, 0, 0, []).

%% CurConns -> 当前连接数目
%% MaxConns -> 最大连接数
loop(State=#state{parent=Parent, ref=Ref,
		transport=Transport, protocol=Protocol, opts=Opts,
		max_conns=MaxConns}, CurConns, NbChildren, Sleepers) ->
	receive
    %% ranch acceptor 获取 client socket 后，发送消息给 conns sup 进程
    %% 此时 client socket 控制进程为 conns sup
		{?MODULE, start_protocol, To, Socket} ->
			case Protocol:start_link(Ref, Socket, Transport, Opts) of %% 启动新进程
				{ok, Pid} ->
					Transport:controlling_process(Socket, Pid),  %% 新进程成为控制进程
					Pid ! {shoot, Ref}, %% 给工作进程发送消息
					put(Pid, true),
					CurConns2 = CurConns + 1,
					if CurConns2 < MaxConns ->
							To ! self(),  %% 给 acceptor 进程发送消息
							loop(State, CurConns2, NbChildren + 1,
								Sleepers);
						true -> %% 如果大于最大连接数，当前 acceptor 进入休眠队列（acceptor进程一直在等待消息）
							loop(State, CurConns2, NbChildren + 1,
								[To|Sleepers])
					end;
				_ ->
					To ! self(),
					loop(State, CurConns, NbChildren, Sleepers)
			end;
		{?MODULE, active_connections, To, Tag} ->
			To ! {Tag, CurConns},
			loop(State, CurConns, NbChildren, Sleepers);
		%% Remove a connection from the count of connections.
		{remove_connection, Ref} ->
			loop(State, CurConns - 1, NbChildren, Sleepers);
		%% Upgrade the max number of connections allowed concurrently.
		%% We resume all sleeping acceptors if this number increases.
		{set_max_conns, MaxConns2} when MaxConns2 > MaxConns ->
			_ = [To ! self() || To <- Sleepers],
			loop(State#state{max_conns=MaxConns2},
				CurConns, NbChildren, []);
		{set_max_conns, MaxConns2} ->
			loop(State#state{max_conns=MaxConns2},
				CurConns, NbChildren, Sleepers);
		%% Upgrade the protocol options.
		{set_opts, Opts2} ->
			loop(State#state{opts=Opts2},
				CurConns, NbChildren, Sleepers);
		{'EXIT', Parent, Reason} ->
			exit(Reason);
		{'EXIT', Pid, _} when Sleepers =:= [] ->
			erase(Pid),
			loop(State, CurConns - 1, NbChildren - 1, Sleepers);
    %% 处理 client socket 的工作进程exit时，发送 EXIT 新号给 master 进程，也就是 conns sup
    %% 回复 sleeping 的acceptor
		{'EXIT', Pid, _} ->
			erase(Pid),
			[To|Sleepers2] = Sleepers,
			To ! self(),
			loop(State, CurConns - 1, NbChildren - 1, Sleepers2);
		{system, From, Request} ->
			sys:handle_system_msg(Request, From, Parent, ?MODULE, [],
				{State, CurConns, NbChildren, Sleepers});
		%% Calls from the supervisor module.
		{'$gen_call', {To, Tag}, which_children} ->
			Pids = get_keys(true),
			Children = [{Protocol, Pid, worker, [Protocol]}
				|| Pid <- Pids],
			To ! {Tag, Children},
			loop(State, CurConns, NbChildren, Sleepers);
		{'$gen_call', {To, Tag}, count_children} ->
			Counts = [{specs, 1}, {active, NbChildren},
				{supervisors, 0}, {workers, NbChildren}],
			To ! {Tag, Counts},
			loop(State, CurConns, NbChildren, Sleepers);
		{'$gen_call', {To, Tag}, _} ->
			To ! {Tag, {error, ?MODULE}},
			loop(State, CurConns, NbChildren, Sleepers)
	end.

system_continue(_, _, {State, CurConns, NbChildren, Sleepers}) ->
	loop(State, CurConns, NbChildren, Sleepers).

-spec system_terminate(any(), _, _, _) -> no_return().
system_terminate(Reason, _, _, _) ->
	exit(Reason).

system_code_change(Misc, _, _, _) ->
	{ok, Misc}.
