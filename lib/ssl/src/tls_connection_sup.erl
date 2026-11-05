%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 2007-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

%%
%%----------------------------------------------------------------------
%% Purpose: Supervisor for a SSL/TLS connection
%%----------------------------------------------------------------------
-module(tls_connection_sup).
-moduledoc false.

-behaviour(supervisor).

%% API
-export([start_link/0, start_link_dist/0]).
-export([start_child/1, start_child_dist/1]).

%% Supervisor callback
-export([init/1]).

%%%=========================================================================
%%%  API
%%%=========================================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_link_dist() ->
    supervisor:start_link({local, tls_dist_connection_sup}, ?MODULE, []).

start_child(Args) ->
    case application:get_env(ssl, connection_tree_owner, supervisor) of
        caller ->
            start_child_in_caller(Args);
        _ ->
            supervisor:start_child(?MODULE, Args)
    end.

start_child_dist(Args) ->
    supervisor:start_child(tls_dist_connection_sup, Args).

%% Start the connection tree from the calling process instead of from this
%% supervisor. supervisor:start_child/2 is a gen_server:call, and the start it
%% performs waits in proc_lib:sync_start/2, a selective receive the compiler
%% cannot mark. Each start therefore scans this supervisor's whole mailbox, so
%% one start costs work proportional to the backlog and a large backlog never
%% clears. Starting in the caller scans the caller's mailbox, which holds
%% almost nothing, and lets starts run in parallel.
start_child_in_caller([SenderArgs, ReceiverArgs]) ->
    case tls_dyn_connection_sup:start_link(SenderArgs, ReceiverArgs) of
        {ok, Sup} = Ok ->
            %% The caller starts the tree but does not supervise it. Drop the
            %% link that supervisor:start_link/2 created, because the tree
            %% shuts down through its significant child on every normal
            %% connection close, and that exit must not reach a caller that
            %% does not trap exits. The connection process monitors the user
            %% process, so a caller that dies still takes the tree with it.
            true = unlink(Sup),
            Ok;
        Other ->
            Other
    end.
    
%%%=========================================================================
%%%  Supervisor callback
%%%=========================================================================
init(_) ->
    SupFlags = #{strategy  => simple_one_for_one, 
                 intensity =>   0,
                 period    => 3600
                },
    ChildSpecs = [#{id      => undefined,
                    restart => temporary,
                    type    => supervisor,
                    start   => {tls_dyn_connection_sup, start_link, []}}],
    {ok, {SupFlags, ChildSpecs}}.


