# Todo CLI

A local Todo CLI written in Gleam. It stores tasks and working hours in a JSON file and can build a deterministic schedule from task estimates, priorities, and deadlines.

## Quick start

Install the project dependencies:

```sh
gleam deps download
```

Configure working hours, add a task, and generate a schedule:

```sh
gleam run -- availability weekly add \
  --day mon,tue,wed,thu,fri --from 09:00 --to 17:00

gleam run -- add "Write report" \
  --estimate 3h --priority 4 --due 2030-07-15 \
  --scheduling-policy asap --minimum-split 30m

gleam run -- schedule
gleam run -- list scheduled --on today
```

Run `gleam run -- --help` for the complete command syntax.

## Commands

| Command | Purpose |
|---|---|
| `add` | Add a task with an optional estimate, priority, due time, scheduling policy, and minimum block length. |
| `list` | List tasks, optionally filtered by status or due date. |
| `done` | Mark a task as completed. |
| `availability` | Manage weekly working hours and date-specific overrides. |
| `schedule` | Replace the saved schedule with a newly generated one. |
| `list scheduled` | Read the saved schedule, optionally filtered by status or date. |

Durations use an integer followed by `m` or `h`. Due values use local time in `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM` form. Priorities range from 1 to 5.

Weekly availability uses `mon` through `sun`. A date override replaces that date's weekly hours: `set` replaces the date with one interval, `add` and `delete` edit its effective intervals, `close` marks it unavailable, and `reset` removes the override.

## Scheduling

A task is eligible when it is pending, has a positive estimate, and has a future due time. Work is placed only inside configured availability, so eligible tasks may remain partly or entirely unscheduled. Higher-priority tasks are favored when there is not enough time.

Scheduling policies control where work is placed before the deadline:

- `asap`: prefer earlier work
- `spread`: distribute work across the available period (default)
- `near_deadline`: prefer later work

`schedule` regenerates the complete saved schedule. Adding or completing tasks and changing availability do not update an existing schedule; run `schedule` again after those changes.

Times are interpreted with the machine's current UTC offset. The generated schedule keeps that fixed offset and does not model timezone database or daylight-saving transitions.

## Storage

The data file is selected in this order:

1. `TODO_FILE`
2. `$XDG_DATA_HOME/todo/tasks.json`
3. `$HOME/.local/share/todo/tasks.json`

A missing file starts an empty task list. Writes replace the file through a sibling temporary file. Concurrent writers are not supported.

## Development

```sh
gleam test --target erlang
scripts/integration_check.sh
gleam build --target erlang
gleam format --check src test
```

See [docs/benchmarking.md](docs/benchmarking.md) before changing the scheduling algorithm or its fixtures.
