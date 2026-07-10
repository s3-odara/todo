#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
run() { TODO_FILE="$tmp/nested/tasks.yaml" gleam run --no-print-progress -- "$@"; }
# list treats only a missing file as empty and does not create it.
TODO_FILE="$tmp/missing/tasks.yaml" gleam run --no-print-progress -- list >/dev/null
[ ! -e "$tmp/missing/tasks.yaml" ]
[ "$(run add 'first' --estimate 3h --priority 5 --due 2026-07-15)" = "Added task 1: first" ]
[ -f "$tmp/nested/tasks.yaml" ]
[ "$(run add 'second')" = "Added task 2: second" ]
[ "$(run list)" = "ID	STATUS	PRIORITY	ESTIMATE	DUE	TITLE
1	pending	5	180m	2026-07-15T23:59	first
2	pending	3	0m	-	second" ]
[ "$(run done 1)" = "Completed task 1: first" ]
[ "$(run list)" = "ID	STATUS	PRIORITY	ESTIMATE	DUE	TITLE
2	pending	3	0m	-	second" ]
[ "$(run list --all)" = "ID	STATUS	PRIORITY	ESTIMATE	DUE	TITLE
1	done	5	180m	2026-07-15T23:59	first
2	pending	3	0m	-	second" ]
# A corrupt existing document must fail and leave destination bytes unchanged.
printf 'tasks: [\n' > "$tmp/corrupt.yaml"
before=$(cksum "$tmp/corrupt.yaml")
if TODO_FILE="$tmp/corrupt.yaml" gleam run --no-print-progress -- add nope >/dev/null 2>/dev/null; then exit 1; else
  [ "$?" -eq 1 ]
fi
[ "$before" = "$(cksum "$tmp/corrupt.yaml")" ]
# Local datetime is retained exactly, with no UTC conversion.
local="$tmp/local.yaml"
TODO_FILE="$local" gleam run --no-print-progress -- add local --due 2026-07-15T18:00 >"$tmp/local.out" 2>"$tmp/local.err"
[ "$(<"$tmp/local.out")" = "Added task 1: local" ]
[ ! -s "$tmp/local.err" ]
grep -Fx '    due: 2026-07-15T18:00' "$local" >/dev/null
# Z and offsets are input errors: stdout is empty, stderr is exact, code is 2,
# and no destination is saved.
for invalid_due in '2026-07-15T18:00Z' '2026-07-15T18:00+09:00'; do
  rejected="$tmp/rejected-$(printf %s "$invalid_due" | tr ':+' '__').yaml"
  if TODO_FILE="$rejected" gleam run --no-print-progress -- add rejected --due "$invalid_due" >"$tmp/out" 2>"$tmp/err"; then exit 1; else
    [ "$?" -eq 2 ]
  fi
  [ ! -s "$tmp/out" ]
  [ "$(<"$tmp/err")" = 'Error: invalid input' ]
  [ ! -e "$rejected" ]
done
# done is numeric/exact only: IDs 1 and 10 do not trigger title or prefix fallback.
exact="$tmp/exact.yaml"
printf '%s\n' 'tasks:' '  - id: 1' '    title: one' '    estimate_minutes: 0' '    priority: 3' '    due: null' '    status: pending' '  - id: 10' '    title: ten' '    estimate_minutes: 0' '    priority: 3' '    due: null' '    status: pending' > "$exact"
[ "$(TODO_FILE="$exact" gleam run --no-print-progress -- done 1)" = 'Completed task 1: one' ]
[ "$(TODO_FILE="$exact" gleam run --no-print-progress -- done 10)" = 'Completed task 10: ten' ]
before=$(cksum "$exact")
if TODO_FILE="$exact" gleam run --no-print-progress -- done ten >"$tmp/out" 2>"$tmp/err"; then exit 1; else
  [ "$?" -eq 2 ]
fi
[ ! -s "$tmp/out" ]
[ "$(<"$tmp/err")" = 'Error: invalid input' ]
[ "$before" = "$(cksum "$exact")" ]
# Semantic input must win over missing path configuration and be code 2.
if env -u TODO_FILE -u XDG_DATA_HOME -u HOME gleam run --no-print-progress -- add x --priority 9 >/dev/null 2>/dev/null; then exit 1; else
  [ "$?" -eq 2 ]
fi
