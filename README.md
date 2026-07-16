# Todo CLI

A local Erlang/BEAM Todo CLI written in Gleam.

```sh
gleam run -- add "レポートを書く" --estimate 3h --priority 3 --due 2026-07-15
gleam run -- list --due today
gleam run -- done 1
gleam run -- list --all
```

## Commands

```text
todo add TITLE [--estimate DURATION] [--priority PRIORITY] [--due DUE]
todo list [--done | --all] [--due today|overdue|YYYY-MM-DD]
          [--due-since YYYY-MM-DD] [--due-until YYYY-MM-DD]
todo done ID
```

`estimate` is an ASCII integer (`0` or non-zero-leading positive) followed by `m` or `h` (so both `0m` and `0h` are valid); its default is `0m`. Priority is 1–5 and defaults to 3. IDs are positive ASCII decimal integers and `done` only accepts an exact ID.

Due input for `add` is a local calendar value. `YYYY-MM-DD` becomes local `YYYY-MM-DDT23:59`; `YYYY-MM-DDTHH:MM` retains its local minute. UTC offsets, `Z`, seconds, and fractional seconds are rejected. The current machine offset converts the input to a UTC timestamp for storage. Output converts that timestamp with the machine's current offset, so changing the offset can change the displayed local time.

`list` shows pending tasks by default, completed tasks with `--done`, and both with `--all`; `--done` and `--all` are mutually exclusive. Due filtering is combined with status filtering using AND and excludes tasks without a due value. `--due YYYY-MM-DD` matches the date after conversion with the current machine offset, `--due today` matches the machine's current local date, and `--due overdue` matches timestamps strictly before the current instant. `--due-since` and `--due-until` compare inclusive local dates and may be used separately or together, but cannot be combined with `--due`. List options are order-independent; duplicate options, reversed ranges, invalid dates, and conflicting options are invalid input.

## Storage

The path is selected by non-empty `TODO_FILE`, then `$XDG_DATA_HOME/todo/tasks.json`, then `$HOME/.local/share/todo/tasks.json`. Tasks are stored as a JSON array; due timestamps are Unix seconds. This format is not compatible with the earlier local-datetime string representation.

Writes use a fixed sibling `.tmp` file and then rename it into place. Failed writes may leave that temporary file behind. There is no locking, fsync, or concurrent-writer guarantee. Reads validate the JSON structure and field types but trust domain values because the file is app-owned.

Exit code 0 is success/help, 1 is path/I/O/corrupt data, and 2 is command grammar, invalid input, missing ID, or already-completed ID. Diagnostics go to stderr and begin with `Error:`.

## Implementation notes

CLI parsing remains pure because the process boundary supplies the current offset as data. The opaque `Due` type wraps its timestamp so deadlines cannot be confused with future schedule timestamps. `gleam_time` converts local due input to absolute instants. List execution samples the current instant and offset once, then injects both into pure filtering and presentation for a coherent result.

## Development

```sh
gleam deps download
gleam format --check src test
gleam test --target erlang
gleam build --target erlang
```
