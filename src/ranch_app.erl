
%% 应用行为模式
-module(ranch_app).
-behaviour(application).

%% API.
-export([start/2]).
-export([stop/1]).
-export([profile_output/0]).

%% API.

start(_, _) ->
	consider_profiling(),
	ranch_sup:start_link().

stop(_) ->
	ok.

-spec profile_output() -> ok.
profile_output() ->
	eprof:stop_profiling(),
	eprof:log("procs.profile"),
	eprof:analyze(procs),
	eprof:log("total.profile"),
	eprof:analyze(total).

%% Internal.

-spec consider_profiling() -> profiling | not_profiling.
consider_profiling() ->
	case application:get_env(profile) of
		{ok, true} ->
			{ok, _Pid} = eprof:start(),
			eprof:start_profiling([self()]);
		_ ->
			not_profiling
	end.
