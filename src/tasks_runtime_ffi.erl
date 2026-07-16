-module(tasks_runtime_ffi).
-export([halt/1, schedulers_online/0]).

halt(Code) -> erlang:halt(Code).

schedulers_online() -> erlang:system_info(schedulers_online).
