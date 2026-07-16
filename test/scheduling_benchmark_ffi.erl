-module(scheduling_benchmark_ffi).
-export([monotonic_microseconds/0]).
monotonic_microseconds() -> erlang:monotonic_time(microsecond).
