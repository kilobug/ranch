
-module(ranch_listener_sup).
-behaviour(supervisor).

%% API.
-export([start_link/6]).

%% supervisor.
-export([init/1]).

%% API.

%% 参数：(tcp_echo, 1, ranch_tcp, [{port, 5555}], echo_protocol, [])
-spec start_link(any(), non_neg_integer(), module(), any(), module(), any())
	-> {ok, pid()}.
start_link(Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts) ->
	MaxConns = proplists:get_value(max_connections, TransOpts, 1024),
	ranch_server:set_new_listener_opts(Ref, MaxConns, ProtoOpts),
	supervisor:start_link(?MODULE, {
		Ref, NbAcceptors, Transport, TransOpts, Protocol
	}).

%% supervisor.

%% 参数：{tcp_echo, 1, ranch_tcp, [{port, 5555}], echo_protocol}
init({Ref, NbAcceptors, Transport, TransOpts, Protocol}) ->
	ChildSpecs = [
		%% conns_sup
		{ranch_conns_sup, {ranch_conns_sup, start_link,
				[Ref, Transport, Protocol]},
			permanent, infinity, supervisor, [ranch_conns_sup]},
		%% acceptors_sup
		{ranch_acceptors_sup, {ranch_acceptors_sup, start_link,
				[Ref, NbAcceptors, Transport, TransOpts]
			}, permanent, infinity, supervisor, [ranch_acceptors_sup]}
	],
  %% 子进程的启动是按照列表顺序从左到右启动，也就是先启动 ranch_conns_sup，再启动 ranch_acceptors_sup
	{ok, {{rest_for_one, 10, 10}, ChildSpecs}}.
