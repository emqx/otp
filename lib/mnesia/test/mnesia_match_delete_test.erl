%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2023. All Rights Reserved.
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
-module(mnesia_match_delete_test).
-include("mnesia_test_lib.hrl").

-export([all/0, groups/0,
         init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).

-export([match_delete/1,
         match_delete_checkpoint/1,
         match_delete_subscribe/1,
         match_delete_index/1,
         match_delete_restart/1,
         match_delete_dump_restart/1,
         match_delete_frag/1]).

all() ->
    [match_delete,
     match_delete_checkpoint,
     match_delete_subscribe,
     match_delete_index,
     match_delete_restart,
     match_delete_dump_restart,
     match_delete_frag].

groups() ->
    [].

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.

init_per_testcase(Func, Conf) ->
    mnesia_test_lib:init_per_testcase(Func, Conf).

end_per_testcase(Func, Conf) ->
    mnesia_test_lib:end_per_testcase(Func, Conf).

match_delete(suite) -> [];
match_delete(Config) when is_list(Config) ->
    [Node1, Node2, Node3] = Nodes = ?acquire_nodes(3, Config),
    Tab = match_delete_tab,
    Def = [{ram_copies, [Node1]}, {disc_copies, [Node2]}, {disc_only_copies, [Node3]}],
    ?match({atomic, ok}, mnesia:create_table(Tab, Def)),
    ?match({atomic, ok}, write(Tab)),
    ?match({atomic, ok}, mnesia:match_delete(Tab, {Tab, '_', bar})),
    ?match({atomic, [1,2,5]}, ?sort(mnesia:transaction(fun() -> mnesia:all_keys(Tab) end))),
    ?verify_mnesia(Nodes, []).

match_delete_checkpoint(suite) -> [];
match_delete_checkpoint(Config) when is_list(Config) ->
    [Node1, Node2, Node3] = Nodes = ?acquire_nodes(3, Config),
    Tab = match_delete_retain_tab,
    Def = [{disc_copies, [Node1, Node2]}, {disc_only_copies, [Node3]}],
    Checkpoint = ?FUNCTION_NAME,
    ?match({atomic, ok}, mnesia:create_table(Tab, Def)),
    ?match({atomic, ok}, write(Tab)),

    ?match({ok, Checkpoint, _}, mnesia:activate_checkpoint([{name, Checkpoint}, {max, [Tab]}])),
    ?match({atomic, ok}, mnesia:match_delete(Tab, {Tab, '_', bar})),
    ?match({atomic, [1,2,5]}, ?sort(mnesia:transaction(fun() -> mnesia:all_keys(Tab) end))),

    File = "match_delete_backup.BUP",
    ?match(ok, mnesia:backup_checkpoint(Checkpoint, File)),
    ?match(ok, mnesia:deactivate_checkpoint(?FUNCTION_NAME)),

    ?match({atomic, [Tab]}, mnesia:restore(File, [{default_op, clear_tables}])),
    ?match({atomic, [1,2,3,4,5]}, ?sort(mnesia:transaction(fun() -> mnesia:all_keys(Tab) end))),

    ?match(ok, file:delete(File)),
    ?verify_mnesia(Nodes, []).

match_delete_subscribe(suite) -> [];
match_delete_subscribe(Config) when is_list(Config) ->
    Nodes = ?acquire_nodes(3, Config),
    Tab = match_delete_sub_tab,
    Def = [{ram_copies, Nodes}],
    ?match({atomic, ok}, mnesia:create_table(Tab, Def)),
    ?match({atomic, ok}, write(Tab)),
    Pattern = {Tab, '_', bar},
    ?match({ok, _}, mnesia:subscribe({table, Tab})),
    ?match({atomic, ok}, mnesia:match_delete(Tab, Pattern)),
    ?match_receive({mnesia_table_event, {delete_object, Pattern, _}}),
    ?match({atomic, [1,2,5]}, ?sort(mnesia:transaction(fun() -> mnesia:all_keys(Tab) end))),
    ?verify_mnesia(Nodes, []).

match_delete_index(suite) -> [];
match_delete_index(Config) when is_list(Config) ->
    Nodes = ?acquire_nodes(3, Config),
    {atomic, ok} = mnesia:create_table(match_delete_index,
                                       [{index, [ix]}, {attributes, [key, ix, val]},
                                        {disc_copies, Nodes}]),
    {atomic, ok} = mnesia:create_table(match_delete_index_ram,
                                       [{index, [ix]}, {attributes, [key, ix, val]},
                                        {ram_copies, Nodes}]),
    {atomic, ok} = mnesia:create_table(match_delete_index_do,
                                       [{index, [ix]}, {attributes, [key, ix, val]},
                                        {disc_only_copies, Nodes}]),
    Test = fun(Tab) ->
                   Rec = {Tab, 1, 4, data},
                   Rec2 = {Tab, 2, 5, data},
                   Rec3 = {Tab, 3, 5, data},
                   Rec4 = {Tab, 4, 6, data},
                   Pattern = {Tab, '_', 5, '_'},

                   {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Rec),
                                                              mnesia:write(Rec2),
                                                              mnesia:write(Rec3),
                                                              mnesia:write(Rec4)
                                                     end),

                   ?match({atomic, ok}, mnesia:match_delete(Tab, Pattern)),

                   ?match([Rec], mnesia:dirty_index_read(Tab, 4, ix)),
                   ?match([Rec4], mnesia:dirty_index_read(Tab, 6, ix)),
                   ?match({atomic, [Rec]}, mnesia:transaction(fun() -> mnesia:index_read(Tab, 4, ix) end)),
                   ?match({atomic, [Rec4]}, mnesia:transaction(fun() -> mnesia:index_read(Tab, 6, ix) end)),

                   ?match([], mnesia:dirty_index_match_object(Pattern, ix)),
                   ?match({atomic, []}, mnesia:transaction(fun() -> mnesia:index_match_object(Pattern, ix) end)),

                   ?match([Rec], mnesia:dirty_index_match_object({Tab, '_', 4, '_'}, ix)),
                   ?match({atomic, [Rec4]},
                          mnesia:transaction(fun() -> mnesia:index_match_object({Tab, '_', 6, data}, ix) end))
           end,
    [Test(Tab) || Tab <- [match_delete_index, match_delete_index_ram, match_delete_index_do]],
    ?verify_mnesia(Nodes, []).

match_delete_restart(suite) -> [];
match_delete_restart(Config) when is_list(Config) ->
    Nodes = ?acquire_nodes(1, Config),
    Tab = match_delete_log_tab,
    Def = [{disc_copies, Nodes}],
    ?match({atomic, ok}, mnesia:create_table(Tab, Def)),
    ?match({atomic, ok}, write(Tab)),
    Pattern = {Tab, '_', bar},
    ?match({atomic, ok}, mnesia:match_delete(Tab, Pattern)),
    %% Restart Mnesia right after calling match_delete/2 to verify that
    %% the table is correctly loaded
    ?match([], mnesia_test_lib:stop_mnesia(Nodes)),
    ?match([], mnesia_test_lib:start_mnesia(Nodes, [Tab])),
    ?match({atomic, [1,2,5]}, ?sort(mnesia:transaction(fun() -> mnesia:all_keys(Tab) end))),
    ?verify_mnesia(Nodes, []).

match_delete_dump_restart(suite) -> [];
match_delete_dump_restart(Config) when is_list(Config) ->
    [Node1] = Nodes = ?acquire_nodes(1, Config),
    Tab = match_delete_dump_tab,
    Def = [{disc_copies, Nodes}],
    ?match({atomic, ok}, mnesia:create_table(Tab, Def)),
    ?match({atomic, ok}, write(Tab)),
    Pattern = {Tab, '_', bar},
    ?match({atomic, ok}, mnesia:match_delete(Tab, Pattern)),
    dumped = rpc:call(Node1, mnesia, dump_log, []),
    ?match({atomic, [1,2,5]}, ?sort(mnesia:transaction(fun() -> mnesia:all_keys(Tab) end))),
    ?match([], mnesia_test_lib:stop_mnesia(Nodes)),
    ?match([], mnesia_test_lib:start_mnesia(Nodes, [Tab])),
    ?match({atomic, [1,2,5]}, ?sort(mnesia:transaction(fun() -> mnesia:all_keys(Tab) end))),
    ?verify_mnesia(Nodes, []).

match_delete_frag(suite) -> [];
match_delete_frag(Config) when is_list(Config) ->
    Nodes = ?acquire_nodes(2, Config),
    Tab = match_delete_frag_tab,
    FragProps = [{n_fragments, 2}, {node_pool, Nodes}],
    Def = [{frag_properties, FragProps}, {ram_copies, Nodes}],
    ?match({atomic, ok}, mnesia:create_table(Tab, Def)),
    KVs = [{1, foo}, {2, foo},
           {3, bar}, {4, bar},
           {5, baz}, {6, baz},
           {7, foo}, {8, foo}],
    ?match([ok, ok | _], frag_write(Tab, KVs)),
    Pattern = {Tab, '_', bar},
    %% match_delete/2 is a transaction itself
    ?match({atomic, ok},
           mnesia:activity(
             async_dirty, fun(P) -> mnesia:match_delete(Tab, P) end, [Pattern], mnesia_frag)
          ),
    Keys = mnesia:activity(transaction, fun() -> mnesia:all_keys(Tab) end, [], mnesia_frag),
    ?match([1,2,5,6,7,8], ?sort(Keys)),
    ?verify_mnesia(Nodes, []).

frag_write(Tab, KVs) ->
    Fun = fun(KVs1) -> [mnesia:write(Tab, {Tab, K, V}, write) || {K, V} <- KVs1] end,
    mnesia:activity(transaction, Fun, [KVs], mnesia_frag).

write(Tab) ->
    mnesia:transaction(
      fun() ->
              mnesia:write({Tab, 1, foo}),
              mnesia:write({Tab, 2, foo}),
              mnesia:write({Tab, 3, bar}),
              mnesia:write({Tab, 4, bar}),
              mnesia:write({Tab, 5, baz})
      end).
