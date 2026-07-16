# Todo CLI

A local Erlang/BEAM Todo CLI written in Gleam. It stores tasks and availability and can generate a deterministic working schedule.

```sh
gleam run -- add "Write report" --estimate 3h --priority 4 --due 2026-07-15 \
  --scheduling-policy asap --minimum-split 30m
gleam run -- availability add --day mon,tue,wed,thu,fri --from 09:00 --to 17:00
gleam run -- schedule
gleam run -- list --scheduled today
gleam run -- done 1
gleam run -- list --scheduled --done
```

## Commands

```text
todo add TITLE [--estimate DURATION] [--priority 1|2|3|4|5] [--due DUE]
               [--scheduling-policy asap|spread|near_deadline]
               [--minimum-split DURATION]
todo list [--done | --all] [--due today|overdue|YYYY-MM-DD]
          [--due-since YYYY-MM-DD] [--due-until YYYY-MM-DD]
todo list --scheduled [today|YYYY-MM-DD] [--done | --all]
todo list [--scheduled-since YYYY-MM-DD] [--scheduled-until YYYY-MM-DD]
          [--done | --all]
todo done ID
todo schedule

todo availability add|delete (--day DAY[,DAY...] | --date YYYY-MM-DD)
                            --from HH:MM --to HH:MM
todo availability set --date YYYY-MM-DD --from HH:MM --to HH:MM
todo availability close|reset --date YYYY-MM-DD
todo availability list
```

Durations are strict ASCII integers followed by `m` or `h`. Estimate defaults to `0m`; minimum split defaults to `30m` and must be positive. Priority defaults to 3. Scheduling policy defaults to `spread`. IDs are positive ASCII decimal integers.

Due input is local `YYYY-MM-DD` (23:59) or `YYYY-MM-DDTHH:MM`, converted to an absolute Unix timestamp with the machine's current UTC offset. UTC suffixes, seconds, fractional seconds, and non-canonical forms are rejected.

Normal `list` defaults to pending tasks; `--done` selects completed tasks and `--all` selects both. Due ranges include both local endpoint dates. Exact/range due filters conflict with scheduled filters, and duplicate, invalid, conflicting, or reversed filters are input errors.

## Availability

Weekdays are `mon,tue,wed,thu,fri,sat,sun`. Times are minute boundaries from `00:00` through `24:00`; `24:00` is valid only as an end. Intervals cannot cross midnight. Add merges overlapping and adjacent intervals, while delete subtracts an interval and may split an existing interval.

A date override completely replaces its weekday's weekly availability. `set` replaces it with one interval; date `add`/`delete` first copy effective weekly intervals when no override exists; `close` stores an empty override; and `reset` removes the override. `availability list` prints weekly entries Monday-first and overrides in date order.

## Automatic scheduling

`schedule` samples the current instant and fixed UTC offset once, rounds the planning start up to a minute boundary, and regenerates every eligible task from scratch. A task is eligible when it is pending, has a positive estimate, has a due time, and its due is after planning start. Other tasks are reported as `completed`, `missing_estimate`, `missing_due`, or `deadline_not_after_start` in that precedence order.

Blocks remain inside effective availability, do not overlap, start no earlier than planning start, end no later than due, and never exceed estimates. Blocks normally meet the task's minimum split. A shorter single block is allowed only when the entire estimate is shorter than the minimum; a leftover shorter than the minimum is not scheduled by itself. Adjacent blocks for one task are merged.

Priority weights are 1, 2, 4, 8, and 16. The scheduler first minimizes priority-weighted unscheduled minutes, then the continuous policy error `integral((actual_progress(x) - desired_progress(x))^2, x=0..1)`. Actual progress is piecewise linear across scheduled blocks and gaps. The implementation integrates each segment exactly with three-point Gauss-Legendre quadrature. With `x` as elapsed calendar fraction from planning start to due, desired completion is:

```text
asap:          1 - (1 - x)^2
spread:        x
near_deadline: x^2
```

A constructive greedy pass orders tasks by priority, deadline, and ID, then places each task at a small set of policy-aware anchors. Deterministic best-improvement hill climbing rebuilds either one task or an ordered pair of tasks, which covers adding, relocating, splitting, merging, and swapping work without separate block-edit operations. The search evaluates at most 20,000 rebuilds per step and accepts at most 1,000 improvements. It is reproducible and constraint-preserving but remains a finite heuristic, not a mathematical global-optimum guarantee.

A successful generation replaces the single saved schedule snapshot. Adding/completing tasks or changing availability does **not** alter that snapshot; only the next `schedule` regenerates it. Scheduled listing reads saved blocks without searching or saving, joins them to current task titles/statuses, and supports all dates, `today`, an explicit date, or inclusive `--scheduled-since`/`--scheduled-until` ranges. Date overlap and display use the offset saved with the schedule. There is no timezone-database or DST transition handling: one fixed offset applies to the whole generated horizon.

## Storage

The path is selected by non-empty `TODO_FILE`, then `$XDG_DATA_HOME/todo/tasks.json`, then `$HOME/.local/share/todo/tasks.json`. Missing files are treated as an empty version 1 state.

Version 1 is one JSON object containing `version`, canonical task and availability arrays, and `current_schedule` (null or metadata plus blocks). Due times, generation metadata, and blocks are Unix seconds; availability intervals are local minutes from midnight. Decoder validation rejects unknown versions, malformed enums/references, duplicate IDs/dates/days, non-canonical intervals, overlapping/non-minute blocks, and non-canonical block order.

Writes use a sibling `.tmp` file and rename. There is no locking, fsync, or concurrent-writer guarantee. Exit code 0 is success/help, 1 is path/I/O/corrupt-state/internal-invariant failure, and 2 is invalid input/domain failure or excessive search space. Diagnostics go to stderr and begin with `Error:`.

## Development

```sh
gleam deps download
gleam format --check src test
gleam test --target erlang
gleam build --target erlang
```

### Scheduling quality benchmark

The deterministic benchmark ranks solutions by the scheduler's lexicographic objective: lower priority-weighted unscheduled minutes first, then lower policy error. Run a suite and save its pipe-separated output with:

```sh
scripts/benchmark_scheduling.sh quick > candidate.psv
```

Available suites are:

- `quick` (default): focused regressions and a small profile matrix for iteration.
- `full`: the tuning profiles with five fixed seeds.
- `holdout`: the same profiles with disjoint seeds; reserve this for validating a proposed algorithm change.
- `oracle`: tiny cases compared with an exhaustive minute-level optimum.
- `stress`: large task sets around the 20,000-candidate boundary; this may take substantially longer.
- `all`: focused, full, holdout, and oracle suites; it deliberately excludes stress.

Each row reports initial and final scores, oracle regret where available, validity, and one timing each for greedy construction and hill climbing. There is no warm-up or repetition. Compilation and availability projection are excluded, and timings are diagnostic rather than part of the quality ranking.

Compare a quick or full result with the checked-in `6af6520` full baseline:

```sh
scripts/compare_scheduling_quality.sh \
  benchmark/baselines/6af6520-full.psv candidate.psv
```

The report's wins and losses are from the candidate's perspective. A full baseline may contain scenarios absent from a quick candidate, but every candidate scenario must have a baseline entry. Policy-error values are comparable only between artifacts using the same objective; artifacts from the former 256-sample objective remain useful for primary-score comparisons only. Comparing holdout or stress results across revisions requires a corresponding result captured from the baseline revision.

Summarize an oracle run without a baseline:

```sh
scripts/benchmark_scheduling.sh oracle > oracle.psv
scripts/compare_scheduling_quality.sh oracle.psv
```

Baseline files contain quality fields only; timings are intentionally excluded. Keep a baseline immutable and add a new commit-named file after intentionally accepting a quality change.
