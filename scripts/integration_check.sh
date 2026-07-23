#!/bin/sh
set -eu

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Keep only process-boundary checks here; command behavior and persistence details
# are covered by focused Gleam tests.
file="$tmp/nested/tasks.json"
if TODO_FILE="$file" gleam run --no-print-progress -- add first >"$tmp/out" 2>"$tmp/err"; then
  code=0
else
  code=$?
fi
[ "$code" -eq 0 ]
grep -Eq '^Added task [0-9a-f]{8}: first$' "$tmp/out"
[ ! -s "$tmp/err" ]
[ -f "$file" ]

# Exercise the real stderr writer and exit-code mapping for persistence errors.
printf '[\n' >"$tmp/corrupt.json"
before=$(cksum "$tmp/corrupt.json")
if TODO_FILE="$tmp/corrupt.json" gleam run --no-print-progress -- list >"$tmp/out" 2>"$tmp/err"; then
  code=0
else
  code=$?
fi
[ "$code" -eq 1 ]
[ ! -s "$tmp/out" ]
[ "$(cat "$tmp/err")" = 'Error: invalid JSON' ]
[ "$before" = "$(cksum "$tmp/corrupt.json")" ]

# Parsing happens before persistence setup; invalid input therefore exits with 2
# even when no storage path can be resolved.
if env -u TODO_FILE -u XDG_DATA_HOME -u HOME gleam run --no-print-progress -- add x --priority 9 >"$tmp/out" 2>"$tmp/err"; then
  code=0
else
  code=$?
fi
[ "$code" -eq 2 ]
[ ! -s "$tmp/out" ]
[ "$(cat "$tmp/err")" = 'Error: invalid input' ]
