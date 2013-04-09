
%% 根监督者
-module(ranch_sup).
-behaviour(supervisor).

%% API.
-export([start_link/0]).

%% supervisor
-export([init/1]).

-define(SUPERVISOR, ?MODULE).

%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
	supervisor:start_link({local, ?SUPERVISOR}, ?MODULE, []).

%% supervisor.

%% 创建一个具名公共 ets 表，用来存储各种配置信息
init([]) ->
	ranch_server = ets:new(ranch_server, [ordered_set, public, named_table]),
	Procs = [
		{ranch_server, {ranch_server, start_link, []},
			permanent, 5000, worker, [ranch_server]}
	],
	{ok, {{one_for_one, 10, 10}, Procs}}.
