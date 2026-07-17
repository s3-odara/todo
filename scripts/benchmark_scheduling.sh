#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
gleam run -m scheduling_benchmark -- "$@"
