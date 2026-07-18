# Representative scheduling fixtures

`representative-workloads-v1.json` is a fixed, hand-curated synthetic corpus. It was authored directly rather than produced by a random or runtime fixture generator. It models plausible workloads but is not derived from telemetry or user data.

All times are integer minutes relative to a planning start of zero. `availability` contains already projected, non-overlapping intervals. Base task IDs are anonymous, fixed, non-sequential integers with no workload meaning.

The benchmark can expand every workload into five metamorphic ID cases: the base assignment, lowbias32 permutations with fixed seeds 101, 211, and 307, and an adversarial assignment that gives smaller IDs to lower-priority tasks with later deadlines. Every variant preserves task order, workload attributes, and the exact ID set; only the task-to-ID mapping changes.

The `representative` suite runs the six base cases, `permutation` runs all 30 cases, and `full` includes only the six base cases to avoid overweighting repeated workloads. `all` adds the 24 non-base permutations without duplicating the base cases already present through `full`.

## Scenarios

| Scenario | Tasks | Availability intervals | Requested/available minutes | Intended characteristic |
|---|---:|---:|---:|---|
| `normal_office_two_weeks` | 24 | 20 | 2700/4140 | Normal weekday office work |
| `overloaded_release_week` | 32 | 10 | 4980/1830 | Severe overload and urgent release work |
| `clustered_month_end_deadlines` | 28 | 12 | 3390/2700 | Two concentrated deadline clusters |
| `meeting_fragmented_week` | 28 | 22 | 2055/1455 | Meeting-created 30–90 minute gaps |
| `deep_work_two_weeks` | 18 | 16 | 5400/4020 | Long tasks and 60–120 minute minimum splits |
| `evenings_and_weekends` | 22 | 17 | 2070/2520 | Weekday evening and weekend use |

The corpus intentionally correlates shorter deadlines with higher priorities, larger estimates with larger minimum splits, and policy choices with task shape: urgent tasks tend toward `asap`, preparatory or long-running work toward `spread`, and submissions or flexible chores toward `near_deadline`.
