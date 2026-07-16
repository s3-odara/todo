#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
exec gleam run -m scheduling_quality_compare -- "$@"
