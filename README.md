# Todo CLI

A local Erlang/BEAM Todo CLI written in Gleam.

```sh
gleam run -- add "レポートを書く" --estimate 3h --priority 3 --due 2026-07-15
gleam run -- list
gleam run -- done 1
gleam run -- list --all
```

## Commands

```text
todo add TITLE [--estimate DURATION] [--priority PRIORITY] [--due DUE]
todo list [--all]
todo done ID
```

`estimate` is an ASCII integer (`0` or non-zero-leading positive) followed by `m` or `h` (so both `0m` and `0h` are valid); its default is `0m`. Priority is 1–5 and defaults to 3. IDs are positive ASCII decimal integers and `done` only accepts an exact ID.

Due values are timezone-free local values. `YYYY-MM-DD` becomes `YYYY-MM-DDT23:59`; `YYYY-MM-DDTHH:MM` is retained. UTC offsets, `Z`, seconds, and fractional seconds are rejected.

## Storage

The path is selected by non-empty `TODO_FILE`, then `$XDG_DATA_HOME/todo/tasks.yaml`, then `$HOME/.local/share/todo/tasks.yaml`. The YAML document has only `tasks` and no schema/version field. Unknown, duplicate, missing, or incorrectly typed keys are corruption errors.

Writes encode fully to a unique sibling temporary file and rename it into place. There is no locking, fsync, concurrent-writer guarantee, or comment/layout preservation.

Exit code 0 is success/help, 1 is path/I/O/corrupt data, and 2 is command grammar, invalid input, missing ID, or already-completed ID. Diagnostics go to stderr and begin with `Error:`.

## Implementation notes

CLI grammar and Gregorian calendar validation are deliberately implemented as small pure modules so exact ASCII grammar and timezone-free due semantics remain explicit. Consequently, the previously planned but unused `glint` and `gleam_time` dependencies are not included; this also avoids their unnecessary transitive ANSI/regex packages. YAML uses Taffy's pure Gleam backend.

## Development

```sh
gleam deps download
gleam format --check src test
gleam test --target erlang
gleam build --target erlang
```
