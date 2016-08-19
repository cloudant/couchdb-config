% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(config_tests).
-behaviour(config_listener).


-include_lib("couch/include/couch_eunit.hrl").
-include_lib("couch/include/couch_db.hrl").


-export([
    handle_config_change/5,
    handle_config_terminate/3
]).


-define(TIMEOUT, 4000).

-define(CONFIG_FIXTURESDIR,
        filename:join([?BUILDDIR(), "src", "config", "test", "fixtures"])).

-define(CONFIG_FIXTURE_1,
        filename:join([?CONFIG_FIXTURESDIR, "config_tests_1.ini"])).

-define(CONFIG_FIXTURE_2,
        filename:join([?CONFIG_FIXTURESDIR, "config_tests_2.ini"])).

-define(CONFIG_DEFAULT_D,
        filename:join([?CONFIG_FIXTURESDIR, "default.d"])).

-define(CONFIG_LOCAL_D,
        filename:join([?CONFIG_FIXTURESDIR, "local.d"])).

-define(CONFIG_FIXTURE_TEMP,
    begin
        FileName = filename:join([?TEMPDIR, "config_temp.ini"]),
        {ok, Fd} = file:open(FileName, write),
        ok = file:truncate(Fd),
        ok = file:close(Fd),
        FileName
    end).

-define(DEPS, [couch_stats, couch_log, config]).


-define(T(F), {erlang:fun_to_list(F), F}).
-define(FEXT(F), fun(_, _) -> F() end).



setup() ->
    setup(?CONFIG_CHAIN).

setup({temporary, Chain}) ->
    setup(Chain);

setup({persistent, Chain}) ->
    setup(Chain ++ [?CONFIG_FIXTURE_TEMP]);

setup(Chain) ->
    ok = application:set_env(config, ini_files, Chain),
    test_util:start_applications(?DEPS).


setup_empty() ->
    setup([]).


setup_config_listener() ->
    setup(),
    spawn_config_listener().

setup_config_notifier(Subscription) ->
    setup(),
    spawn_config_notifier(Subscription).


teardown(Pid) when is_pid(Pid) ->
    catch exit(Pid, kill),
    teardown(undefined);

teardown(_) ->
    [application:stop(App) || App <- ?DEPS].

teardown(_, Pid) when is_pid(Pid) ->
    catch exit(Pid, kill),
    teardown(undefined);
teardown(_, _) ->
    teardown(undefined).


handle_config_change("remove_handler", _Key, _Value, _Persist, {_Pid, _State}) ->
    remove_handler;

handle_config_change("update_state", Key, Value, Persist, {Pid, State}) ->
    Pid ! {config_msg, {{"update_state", Key, Value, Persist}, State}},
    {ok, {Pid, Key}};

handle_config_change("throw_error", _Key, _Value, _Persist, {_Pid, _State}) ->
    throw(this_is_an_error);

handle_config_change(Section, Key, Value, Persist, {Pid, State}) ->
    Pid ! {config_msg, {{Section, Key, Value, Persist}, State}},
    {ok, {Pid, State}}.


handle_config_terminate(Self, Reason, {Pid, State}) ->
    Pid ! {config_msg, {Self, Reason, State}},
    ok.


config_get_test_() ->
    {
        "Config get tests",
        {
            foreach,
            fun setup/0,
            fun teardown/1,
            [
                fun should_load_all_configs/0,
                fun should_locate_daemons_section/0,
                fun should_locate_mrview_handler/0,
                fun should_return_undefined_atom_on_missed_section/0,
                fun should_return_undefined_atom_on_missed_option/0,
                fun should_return_custom_default_value_on_missed_option/0,
                fun should_only_return_default_on_missed_option/0,
                fun should_fail_to_get_binary_value/0,
                fun should_return_any_supported_default/0
            ]
        }
    }.


config_set_test_() ->
    {
        "Config set tests",
        {
            foreach,
            fun setup/0,
            fun teardown/1,
            [
                fun should_update_option/0,
                fun should_create_new_section/0,
                fun should_fail_to_set_binary_value/0
            ]
        }
    }.


config_del_test_() ->
    {
        "Config deletion tests",
        {
            foreach,
            fun setup/0,
            fun teardown/1,
            [
                fun should_return_undefined_atom_after_option_deletion/0,
                fun should_be_ok_on_deleting_unknown_options/0
            ]
        }
    }.


config_override_test_() ->
    {
        "Configs overide tests",
        {
            foreachx,
            fun setup/1,
            fun teardown/2,
            [
                {{temporary, [?CONFIG_DEFAULT]},
                        fun should_ensure_in_defaults/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_FIXTURE_1]},
                        fun should_override_options/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_FIXTURE_2]},
                        fun should_create_new_sections_on_override/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_FIXTURE_1,
                                ?CONFIG_FIXTURE_2]},
                        fun should_win_last_in_chain/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_DEFAULT_D]},
                        fun should_read_default_d/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_LOCAL_D]},
                        fun should_read_local_d/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_DEFAULT_D,
                                ?CONFIG_LOCAL_D]},
                        fun should_read_default_and_local_d/2}
            ]
        }
    }.


config_persistent_changes_test_() ->
    {
        "Config persistent changes",
        {
            foreachx,
            fun setup/1,
            fun teardown/2,
            [
                {{persistent, [?CONFIG_DEFAULT]},
                        fun should_write_changes/2},
                {{temporary, [?CONFIG_DEFAULT]},
                        fun should_ensure_default_wasnt_modified/2},
                {{temporary, [?CONFIG_FIXTURE_TEMP]},
                        fun should_ensure_written_to_last_config_in_chain/2}
            ]
        }
    }.


config_no_files_test_() ->
    {
        "Test config with no files",
        {
            foreach,
            fun setup_empty/0,
            fun teardown/1,
            [
                fun should_ensure_that_no_ini_files_loaded/0,
                fun should_create_non_persistent_option/0,
                fun should_create_persistent_option/0
            ]
        }
    }.


config_listener_behaviour_test_() ->
    {
        "Test config_listener behaviour",
        {
            foreach,
            local,
            fun setup_config_listener/0,
            fun teardown/1,
            [
                fun should_handle_value_change/1,
                fun should_pass_correct_state_to_handle_config_change/1,
                fun should_pass_correct_state_to_handle_config_terminate/1,
                fun should_pass_subscriber_pid_to_handle_config_terminate/1,
                fun should_not_call_handle_config_after_related_process_death/1,
                fun should_remove_handler_when_requested/1,
                fun should_remove_handler_when_pid_exits/1,
                fun should_stop_monitor_on_error/1
            ]
        }
    }.

config_notifier_behaviour_test_() ->
    {
        "Test config_notifier behaviour",
        {
            foreachx,
            local,
            fun setup_config_notifier/1,
            fun teardown/2,
            [
                {all, fun should_notify/2},
                {["section_foo"], fun should_notify/2},
                {[{"section_foo", "key_bar"}], fun should_notify/2},
                {["section_foo"], fun should_not_notify/2},
                {[{"section_foo", "key_bar"}], fun should_not_notify/2},
                {all, fun should_unsubscribe_when_subscriber_gone/2},
                {all, fun should_not_add_duplicate/2}
            ]
        }
    }.


should_load_all_configs() ->
    ?assert(length(config:all()) > 0).


should_locate_daemons_section() ->
    ?assert(length(config:get("daemons")) > 0).


should_locate_mrview_handler() ->
    Expect = "{couch_mrview_http, handle_view_req}",
    ?assertEqual(Expect, config:get("httpd_design_handlers", "_view")).


should_return_undefined_atom_on_missed_section() ->
    ?assertEqual(undefined, config:get("foo", "bar")).


should_return_undefined_atom_on_missed_option() ->
    ?assertEqual(undefined, config:get("httpd", "foo")).


should_return_custom_default_value_on_missed_option() ->
    ?assertEqual("bar", config:get("httpd", "foo", "bar")).


should_only_return_default_on_missed_option() ->
    ?assertEqual("0", config:get("httpd", "port", "bar")).


should_fail_to_get_binary_value() ->
    ?assertException(error, badarg, config:get(<<"a">>, <<"b">>, <<"c">>)).


should_return_any_supported_default() ->
    Values = [undefined, "list", true, false, 0.1, 1],
    lists:map(fun(V) ->
        ?assertEqual(V, config:get(<<"foo">>, <<"bar">>, V))
    end, Values).


should_update_option() ->
    ok = config:set("mock_log", "level", "severe", false),
    ?assertEqual("severe", config:get("mock_log", "level")).


should_create_new_section() ->
    ?assertEqual(undefined, config:get("new_section", "bizzle")),
    ?assertEqual(ok, config:set("new_section", "bizzle", "bang", false)),
    ?assertEqual("bang", config:get("new_section", "bizzle")).


should_fail_to_set_binary_value() ->
    ?assertException(error, badarg,
            config:set(<<"a">>, <<"b">>, <<"c">>, false)).


should_return_undefined_atom_after_option_deletion() ->
    ?assertEqual(ok, config:delete("mock_log", "level", false)),
    ?assertEqual(undefined, config:get("mock_log", "level")).


should_be_ok_on_deleting_unknown_options() ->
    ?assertEqual(ok, config:delete("zoo", "boo", false)).


should_ensure_in_defaults(_, _) ->
    ?_test(begin
        ?assertEqual("500", config:get("couchdb", "max_dbs_open")),
        ?assertEqual("5986", config:get("httpd", "port")),
        ?assertEqual(undefined, config:get("fizbang", "unicode"))
    end).


should_override_options(_, _) ->
    ?_test(begin
        ?assertEqual("10", config:get("couchdb", "max_dbs_open")),
        ?assertEqual("4895", config:get("httpd", "port"))
    end).


should_read_default_d(_, _) ->
    ?_test(begin
        ?assertEqual("11", config:get("couchdb", "max_dbs_open"))
    end).


should_read_local_d(_, _) ->
    ?_test(begin
        ?assertEqual("12", config:get("couchdb", "max_dbs_open"))
    end).


should_read_default_and_local_d(_, _) ->
    ?_test(begin
        ?assertEqual("12", config:get("couchdb", "max_dbs_open"))
    end).


should_create_new_sections_on_override(_, _) ->
    ?_test(begin
        ?assertEqual("80", config:get("httpd", "port")),
        ?assertEqual("normalized", config:get("fizbang", "unicode"))
    end).


should_win_last_in_chain(_, _) ->
    ?_test(begin
        ?assertEqual("80", config:get("httpd", "port"))
    end).


should_write_changes(_, _) ->
    ?_test(begin
        ?assertEqual("5986", config:get("httpd", "port")),
        ?assertEqual(ok, config:set("httpd", "port", "8080")),
        ?assertEqual("8080", config:get("httpd", "port")),
        ?assertEqual(ok, config:delete("httpd", "bind_address", "8080")),
        ?assertEqual(undefined, config:get("httpd", "bind_address"))
    end).


should_ensure_default_wasnt_modified(_, _) ->
    ?_test(begin
        ?assertEqual("5986", config:get("httpd", "port")),
        ?assertEqual("127.0.0.1", config:get("httpd", "bind_address"))
    end).


should_ensure_written_to_last_config_in_chain(_, _) ->
    ?_test(begin
        ?assertEqual("8080", config:get("httpd", "port")),
        ?assertEqual(undefined, config:get("httpd", "bind_address"))
    end).


should_ensure_that_no_ini_files_loaded() ->
    ?assertEqual(0, length(config:all())).


should_create_non_persistent_option() ->
    ?_test(begin
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        ?assertEqual("80", config:get("httpd", "port"))
    end).


should_create_persistent_option() ->
    ?_test(begin
        ?assertEqual(ok, config:set("httpd", "bind_address", "127.0.0.1")),
        ?assertEqual("127.0.0.1", config:get("httpd", "bind_address"))
    end).


should_handle_value_change(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        ?assertMatch({{"httpd", "port", "80", false}, _}, getmsg(Pid))
    end).


should_pass_correct_state_to_handle_config_change(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("update_state", "foo", "any", false)),
        ?assertMatch({_, undefined}, getmsg(Pid)),
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        ?assertMatch({_, "foo"}, getmsg(Pid))
    end).


should_pass_correct_state_to_handle_config_terminate(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("update_state", "foo", "any", false)),
        ?assertMatch({_, undefined}, getmsg(Pid)),
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        ?assertMatch({_, "foo"}, getmsg(Pid)),
        ?assertEqual(ok, config:set("remove_handler", "any", "any", false)),
        ?assertEqual({Pid, remove_handler, "foo"}, getmsg(Pid))
    end).


should_pass_subscriber_pid_to_handle_config_terminate(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("remove_handler", "any", "any", false)),
        ?assertEqual({Pid, remove_handler, undefined}, getmsg(Pid))
    end).


should_not_call_handle_config_after_related_process_death(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("remove_handler", "any", "any", false)),
        ?assertEqual({Pid, remove_handler, undefined}, getmsg(Pid)),
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        Event = receive
            {config_msg, _} -> got_msg
            after 250 -> no_msg
        end,
        ?assertEqual(no_msg, Event)
    end).


should_remove_handler_when_requested(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),
        ?assertEqual(ok, config:set("remove_handler", "any", "any", false)),
        ?assertEqual({Pid, remove_handler, undefined}, getmsg(Pid)),
        ?assertEqual(0, n_handlers())
    end).


should_remove_handler_when_pid_exits(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),

        % Monitor the config_listener_mon process
        {monitored_by, [Mon]} = process_info(Pid, monitored_by),
        MonRef = erlang:monitor(process, Mon),

        % Kill the process synchronously
        PidRef = erlang:monitor(process, Pid),
        exit(Pid, kill),
        receive
            {'DOWN', PidRef, _, _, _} -> ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_listener_death})
        end,

        % Wait for the config_listener_mon process to
        % exit to indicate the handler has been removed.
        receive
            {'DOWN', MonRef, _, _, normal} -> ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_listener_mon_death})
        end,

        ?assertEqual(0, n_handlers())
    end).


should_stop_monitor_on_error(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),

        % Monitor the config_listener_mon process
        {monitored_by, [Mon]} = process_info(Pid, monitored_by),
        MonRef = erlang:monitor(process, Mon),

        % Have the process throw an error
        ?assertEqual(ok, config:set("throw_error", "foo", "bar", false)),

        % Make sure handle_config_terminate is called
        ?assertEqual({Pid, {error, this_is_an_error}, undefined}, getmsg(Pid)),

        % Wait for the config_listener_mon process to
        % exit to indicate the handler has been removed
        % due to an error
        receive
            {'DOWN', MonRef, _, _, shutdown} -> ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_listener_mon_shutdown})
        end,

        ?assertEqual(0, n_handlers())
    end).

should_notify(Subscription, Pid) ->
    {to_string(Subscription), ?_test(begin
        ?assertEqual(ok, config:set("section_foo", "key_bar", "any", false)),
        ?assertEqual({config_change,"section_foo", "key_bar", "any", false}, getmsg(Pid)),
        ok
    end)}.

should_not_notify([{Section, _}] = Subscription, Pid) ->
    {to_string(Subscription), ?_test(begin
        ?assertEqual(ok, config:set(Section, "any", "any", false)),
        ?assertError({timeout, config_msg}, getmsg(Pid)),
        ok
    end)};
should_not_notify(Subscription, Pid) ->
    {to_string(Subscription), ?_test(begin
        ?assertEqual(ok, config:set("any", "any", "any", false)),
        ?assertError({timeout, config_msg}, getmsg(Pid)),
        ok
    end)}.

should_unsubscribe_when_subscriber_gone(_Subscription, Pid) ->
    ?_test(begin
        ?assertEqual(1, n_notifiers()),

        ?assert(is_process_alive(Pid)),

        % Monitor subscriber process
        MonRef = erlang:monitor(process, Pid),

        exit(Pid, kill),

        % Wait for the subscriber process to exit
        receive
            {'DOWN', MonRef, _, _, _} -> ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_notifier_shutdown})
        end,

        ?assertNot(is_process_alive(Pid)),

        ?assertEqual(0, n_notifiers()),
        ok
    end).

should_not_add_duplicate(_, _) ->
    ?_test(begin
        ?assertEqual(1, n_notifiers()), %% spawned from setup

        ?assertMatch(ok, config:subscribe_for_changes(all)),

        ?assertEqual(2, n_notifiers()),

        ?assertMatch(ok, config:subscribe_for_changes(all)),

        ?assertEqual(2, n_notifiers()),
        ok
    end).


spawn_config_listener() ->
    Self = self(),
    Pid = erlang:spawn(fun() ->
        ok = config:listen_for_changes(?MODULE, {self(), undefined}),
        Self ! registered,
        loop(undefined)
    end),
    receive
        registered -> ok
    after ?TIMEOUT ->
        erlang:error({timeout, config_handler_register})
    end,
    Pid.

spawn_config_notifier(Subscription) ->
    Self = self(),
    Pid = erlang:spawn(fun() ->
        ok = config:subscribe_for_changes(Subscription),
        Self ! registered,
        loop(undefined)
    end),
    receive
        registered -> ok
    after ?TIMEOUT ->
        erlang:error({timeout, config_handler_register})
    end,
    Pid.


loop(undefined) ->
    receive
        {config_msg, _} = Msg ->
            loop(Msg);
        {config_change, _, _, _, _} = Msg ->
            loop({config_msg, Msg});
        {get_msg, _, _} = Msg ->
            loop(Msg);
        Msg ->
            erlang:error({invalid_message, Msg})
    end;

loop({get_msg, From, Ref}) ->
    receive
        {config_msg, _} = Msg ->
            From ! {Ref, Msg};
        {config_change, _, _, _, _} = Msg ->
            From ! {Ref, Msg};
        Msg ->
            erlang:error({invalid_message, Msg})
    end,
    loop(undefined);

loop({config_msg, _} = Msg) ->
    receive
        {get_msg, From, Ref} ->
            From ! {Ref, Msg};
        Msg ->
            erlang:error({invalid_message, Msg})
    end,
    loop(undefined).


getmsg(Pid) ->
    Ref = erlang:make_ref(),
    Pid ! {get_msg, self(), Ref},
    receive
        {Ref, {config_msg, Msg}} -> Msg
    after ?TIMEOUT ->
        erlang:error({timeout, config_msg})
    end.


n_handlers() ->
    Handlers = gen_event:which_handlers(config_event),
    length([Pid || {config_listener, {?MODULE, Pid}} <- Handlers]).

n_notifiers() ->
    Handlers = gen_event:which_handlers(config_event),
    length([Pid || {config_notifier, Pid} <- Handlers]).

to_string(Term) ->
    lists:flatten(io_lib:format("~p", [Term])).
