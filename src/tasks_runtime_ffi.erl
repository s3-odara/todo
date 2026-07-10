-module(tasks_runtime_ffi).
-export([halt/1, unique_integer/0]).
halt(Code) -> erlang:halt(Code).
unique_integer() -> erlang:unique_integer([positive, monotonic]).
