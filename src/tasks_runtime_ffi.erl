-module(tasks_runtime_ffi).
-export([halt/1]).

halt(Code) -> erlang:halt(Code).
