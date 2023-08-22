%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2021. All Rights Reserved.
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

-module(mnesia_hook).

-include("mnesia.hrl").

-export([
         register_hook/2,
         unregister_hook/1,
         do_post_commit/2
        ]).

-define(hook(NAME), {mnesia_hook, NAME}).

-type post_commit_hook_data() ::
        #{ node => node()
         , ram_copies => list()
         , disc_copies => list()
         , disc_only_copies => list()
         , ext => list()
         , schema_ops => list()
         }.

-type post_commit_hook() :: fun((_Tid, post_commit_hook_data()) -> ok).

-spec register_hook(post_commit, post_commit_hook()) -> ok | {error, term()}.
register_hook(post_commit, Hook) when is_function(Hook, 2) ->
    persistent_term:put(?hook(post_commit), Hook);
register_hook(_, _) ->
    {error, bad_type}.

-spec unregister_hook(post_commit) -> boolean() | {error, term()}.
unregister_hook(post_commit) ->
    persistent_term:erase(?hook(post_commit));
unregister_hook(_) ->
    {error, bad_type}.

-spec do_post_commit(_Tid, #commit{}) -> ok.
do_post_commit(Tid, Commit) ->
    case persistent_term:get(?hook(post_commit), undefined) of
        undefined ->
            ok;
        Fun ->
            #commit{ node = Node
                   , ram_copies = Ram
                   , disc_copies = Disc
                   , disc_only_copies = DiscOnly
                   , ext = Ext
                   , schema_ops = SchemaOps
                   } = Commit,
            CommitData = #{ node => Node
                          , ram_copies => Ram
                          , disc_copies => Disc
                          , disc_only_copies => DiscOnly
                          , ext => Ext
                          , schema_ops => SchemaOps
                          },
            try Fun(Tid, CommitData)
            catch EC:Err:St ->
                    CommitTabs = commit_tabs(Ram, Disc, DiscOnly, Ext),
                    mnesia_lib:dbg_out("Mnesia post_commit hook failed: ~p:~p~nStacktrace:~p~nCommit tables:~p~n",
                                       [EC, Err, stack_without_args(St), CommitTabs])
            end,
            ok
    end.

%% May be helpful for debugging
commit_tabs(Ram, Disc, DiscOnly, Ext) ->
    Acc = tabs_from_ops(Ram, []),
    Acc1 = tabs_from_ops(Disc, Acc),
    Acc2 = tabs_from_ops(DiscOnly, Acc1),
    lists:uniq(tabs_from_ops(Ext, Acc2)).

tabs_from_ops([{{Tab, _K}, _Val, _Op} | T], Acc) ->
    tabs_from_ops(T, [Tab | Acc]);
tabs_from_ops([_ | T], Acc) ->
    tabs_from_ops(T, Acc);
tabs_from_ops([], Acc) ->
    Acc.

%% Args may contain sensitive data
stack_without_args([{M, F, Args, Info} | T]) when is_list(Args) ->
    [{M, F, length(Args), Info} | stack_without_args(T)];
stack_without_args([StItem | T] ) ->
    [StItem | stack_without_args(T)];
stack_without_args([]) ->
    [].
