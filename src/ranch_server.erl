
%% ranch_server 是 gen_server 实现，用来维护配置信息，底层存储使用 ets 。
%% 当调用 ranch_server 提供的 api 时，调用进程向 ranch_server 进程发送携带参数的消息
%% ranch_server 进程处理此消息，一般是向ets表中插入记录
-module(ranch_server).
-behaviour(gen_server).

%% API.
-export([start_link/0]).
-export([set_new_listener_opts/3]).
-export([cleanup_listener_opts/1]).
-export([set_connections_sup/2]).
-export([get_connections_sup/1]).
-export([set_port/2]).
-export([get_port/1]).
-export([set_max_connections/2]).
-export([get_max_connections/1]).
-export([set_protocol_options/2]).
-export([get_protocol_options/1]).
-export([count_connections/1]).

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-define(TAB, ?MODULE).

%% ranch_server 进程对其他进程监控的引用，包括 conns sup 进程
-type monitors() :: [{{reference(), pid()}, any()}].
-record(state, {
	monitors = [] :: monitors()
}).

%% API.

%% 启动ranch_server
-spec start_link() -> {ok, pid()}.
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% 设置 listener 参数
%% 参数：(tcp_echo, 1024, ProtoOpts)
-spec set_new_listener_opts(any(), ranch:max_conns(), any()) -> ok.
set_new_listener_opts(Ref, MaxConns, Opts) ->
	gen_server:call(?MODULE, {set_new_listener_opts, Ref, MaxConns, Opts}).

%% listener 停止后，清空相关参数
-spec cleanup_listener_opts(any()) -> ok.
cleanup_listener_opts(Ref) ->
	_ = ets:delete(?TAB, {port, Ref}),
	_ = ets:delete(?TAB, {max_conns, Ref}),
	_ = ets:delete(?TAB, {opts, Ref}),
	ok.

%% 设置 conns sup
-spec set_connections_sup(any(), pid()) -> ok.
set_connections_sup(Ref, Pid) ->
	true = gen_server:call(?MODULE, {set_connections_sup, Ref, Pid}),
	ok.

%% 查询 conns sup 的pid
-spec get_connections_sup(any()) -> pid().
get_connections_sup(Ref) ->
	ets:lookup_element(?TAB, {conns_sup, Ref}, 2).

%% 设置端口号
-spec set_port(any(), inet:port_number()) -> ok.
set_port(Ref, Port) ->
	gen_server:call(?MODULE, {set_port, Ref, Port}).

%% 查询端口号
-spec get_port(any()) -> inet:port_number().
get_port(Ref) ->
	ets:lookup_element(?TAB, {port, Ref}, 2).

%% 设置最大连接数
-spec set_max_connections(any(), ranch:max_conns()) -> ok.
set_max_connections(Ref, MaxConnections) ->
	gen_server:call(?MODULE, {set_max_conns, Ref, MaxConnections}).

%% 返回最大连接数
-spec get_max_connections(any()) -> ranch:max_conns().
get_max_connections(Ref) ->
	ets:lookup_element(?TAB, {max_conns, Ref}, 2).

%% 设置协议选项
-spec set_protocol_options(any(), any()) -> ok.
set_protocol_options(Ref, ProtoOpts) ->
	gen_server:call(?MODULE, {set_opts, Ref, ProtoOpts}).

%% 查询协议选项
-spec get_protocol_options(any()) -> any().
get_protocol_options(Ref) ->
	ets:lookup_element(?TAB, {opts, Ref}, 2).

%% 查询连接数
-spec count_connections(any()) -> non_neg_integer().
count_connections(Ref) ->
	ranch_conns_sup:active_connections(get_connections_sup(Ref)).

%% gen_server.

init([]) ->
	Monitors = [{{erlang:monitor(process, Pid), Pid}, Ref} ||
		[Ref, Pid] <- ets:match(?TAB, {{conns_sup, '$1'}, '$2'})],
	{ok, #state{monitors=Monitors}}.

%% ets 表中保存最大连接数和协议选项
%% 参数：{set_new_listener_opts, tcp_echo, 1024, ProtoOpts}
handle_call({set_new_listener_opts, Ref, MaxConns, Opts}, _, State) ->
	ets:insert(?TAB, {{max_conns, Ref}, MaxConns}),
	ets:insert(?TAB, {{opts, Ref}, Opts}),
	{reply, ok, State};
%% 保存 conns sup，也就是连接控制进程
%% 同时 ranch_server 进程还要去监控 conns sup 进程
handle_call({set_connections_sup, Ref, Pid}, _,
		State=#state{monitors=Monitors}) ->
	case ets:insert_new(?TAB, {{conns_sup, Ref}, Pid}) of
		true ->
			MonitorRef = erlang:monitor(process, Pid),
			{reply, true,
				State#state{monitors=[{{MonitorRef, Pid}, Ref}|Monitors]}};
		false ->
			{reply, false, State}
	end;
handle_call({set_port, Ref, Port}, _, State) ->
	true = ets:insert(?TAB, {{port, Ref}, Port}),
	{reply, ok, State};
handle_call({set_max_conns, Ref, MaxConns}, _, State) ->
	ets:insert(?TAB, {{max_conns, Ref}, MaxConns}),
	ConnsSup = get_connections_sup(Ref),
	ConnsSup ! {set_max_conns, MaxConns},
	{reply, ok, State};
handle_call({set_opts, Ref, Opts}, _, State) ->
	ets:insert(?TAB, {{opts, Ref}, Opts}),
	ConnsSup = get_connections_sup(Ref),
	ConnsSup ! {set_opts, Opts},
	{reply, ok, State};
handle_call(_Request, _From, State) ->
	{reply, ignore, State}.

handle_cast(_Request, State) ->
	{noreply, State}.

handle_info({'DOWN', MonitorRef, process, Pid, _},
		State=#state{monitors=Monitors}) ->
	{_, Ref} = lists:keyfind({MonitorRef, Pid}, 1, Monitors),
	true = ets:delete(?TAB, {conns_sup, Ref}),
	Monitors2 = lists:keydelete({MonitorRef, Pid}, 1, Monitors),
	{noreply, State#state{monitors=Monitors2}};
handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.
