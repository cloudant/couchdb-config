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

-module(config_notifier).

-behaviour(gen_event).
-vsn(1).

%% Public interface
-export([subscribe/1]).
-export([subscribe/2]).

-export([behaviour_info/1]).

%% gen_event interface
-export([
    init/1,
    handle_event/2,
    handle_call/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

behaviour_info(callbacks) ->
    [{handle_config_change,5},
     {handle_config_terminate, 3}];
behaviour_info(_) ->
    undefined.

subscribe(Subscription) ->
    subscribe(self(), Subscription).

subscribe(Subscriber, Subscription) ->
    gen_event:add_sup_handler(
        config_event, {?MODULE, Subscriber}, {Subscriber, Subscription}).

init({Subscriber, Subscription}) ->
    {ok, {Subscriber, Subscription}}.

handle_event({config_change, _, _, _, _} = Event, {Subscriber, Subscription}) ->
    maybe_notify(Event, Subscriber, Subscription).

handle_call(_Request, St) ->
    {ok, ignored, St}.

handle_info(_Info, St) ->
    {ok, St}.

terminate(_Reason, {_Subscriber, _Subscription}) ->
    ok.

code_change(_OldVsn, St, _Extra) ->
    {ok, St}.

maybe_notify(Event, Subscriber, all) ->
    Subscriber ! Event;
maybe_notify({config_change, Sec, Key, _, _} = Event, Subscriber, Subscription) ->
    case should_notify(Sec, Key, Subscription) of
        true ->
            Subscriber ! Event;
        false ->
            ok
    end.

should_notify(Sec, Key, Subscription) ->
    lists:any(fun(S) -> S =:= Sec orelse S =:= {Sec, Key} end, Subscription).
