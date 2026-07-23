# Scheduling benchmarks

Use these benchmarks when changing the scheduler. They compare solutions in this order:

1. priority-weighted unscheduled minutes (lower is better)
2. scheduling-policy error (lower is better)

Timings are diagnostic only. Each case runs once, without warm-up; compilation and availability projection are excluded.

## Production search

`scheduler.generate` is the single generation path. It always constructs the
unchanged greedy schedule first, then applies an adaptive Simple SA search with
the fixed production seed `101`. No RNG entropy is read from a clock or global
state.

Empty inputs and inputs with a nonpositive weighted estimate return greedy
immediately. Otherwise, the adaptive gate explicitly checks actual unweighted
unscheduled minutes per task (`estimate_minutes - placed_minutes`, when
positive). If any actual minutes remain, the search runs the full 16,384
iterations. If greedy places every requested minute, search runs a 1,024
iteration probe. A probe best continues only when `score.strictly_better`
considers it meaningfully better: any primary reduction qualifies, while a
policy-only reduction must exceed epsilon. Exact lexicographic comparison still
tracks the best-ever candidate and selects the final result. Continuation keeps
the same current, best, RNG, and absolute iteration state through 16,384 total
iterations; search is not restarted and its random stream and cooling schedule
are unchanged. With no meaningful probe improvement, generation returns greedy.

Every search starts from seed `101`. Workloads intentionally share the same
random stream; their task counts, candidate sets, and accepted transitions make
the actual searches diverge. The internal `simple_sa.improve` boundary retains
an explicit seed so benchmarks can reproduce other streams, but scheduler
callers cannot select a mode or seed.

## Common workflow

Run the quick suite while iterating:

```sh
scripts/benchmark_scheduling.sh quick > candidate.psv
scripts/compare_scheduling_quality.sh \
  benchmark/baselines/17f87e7-full.psv candidate.psv
```

Before accepting an algorithm change, run `full`, then validate it against the separate `holdout` suite and baseline:

```sh
scripts/benchmark_scheduling.sh full > full-candidate.psv
scripts/compare_scheduling_quality.sh \
  benchmark/baselines/17f87e7-full.psv full-candidate.psv

scripts/benchmark_scheduling.sh holdout > holdout-candidate.psv
scripts/compare_scheduling_quality.sh \
  benchmark/baselines/17f87e7-holdout.psv holdout-candidate.psv
```

Wins and losses are reported from the candidate's perspective. Positive quality-loss percentages are regressions. Compare policy error only when both results use the same objective and schema.

## Suites

| Suite | Use |
|---|---|
| `quick` | Focused regressions and a small profile matrix for iteration. This is the default. |
| `full` | Main tuning suite, including generated profiles and the six representative workloads. |
| `holdout` | Disjoint cases used only to validate a proposed change. |
| `oracle` | Small cases checked against exhaustive or cached optimal results. |
| `representative` | The six fixed representative workloads. |
| `permutation` | Representative workloads under 30 task-ID assignments. |
| `all` | `full`, `holdout`, `oracle`, and non-base representative permutations. |

The result file includes workload size, initial and final quality, unscheduled
minutes by priority, oracle regret where available, block counts, timings, and
validity. Baseline files retain quality fields but omit timings.
`search_iterations` reports the actual number of attempted adaptive-search
iterations (`0`, `1024`, or `16384`), and `simple_sa_us` reports elapsed adaptive
Simple SA time.

## Baselines

Baselines are immutable records of an accepted revision. The checked-in `17f87e7` files are the current full and holdout baselines.

When an intentional scheduler, sampler, or fixture change is accepted:

1. commit the change
2. run both `full` and `holdout` at that revision
3. save new baseline files named with the commit ID
4. keep the old baselines

A quick result may contain fewer scenarios than its full baseline, but every candidate scenario must exist in the baseline. Results from `holdout` or `permutation` need a corresponding baseline result for cross-revision comparison.

## Representative workloads

`benchmark/fixtures/representative-workloads-v1.json` is a fixed synthetic corpus, not telemetry or user data. Times are integer minutes relative to planning start. Availability intervals are already projected and non-overlapping.

| Scenario | Tasks | Availability intervals | Requested / available minutes | Characteristic |
|---|---:|---:|---:|---|
| `normal_office_two_weeks` | 24 | 20 | 2700 / 4140 | Normal weekday office work |
| `overloaded_release_week` | 32 | 10 | 4980 / 1830 | Severe overload and urgent release work |
| `clustered_month_end_deadlines` | 28 | 12 | 3390 / 2700 | Two concentrated deadline clusters |
| `meeting_fragmented_week` | 28 | 22 | 2055 / 1455 | Meeting-created 30–90 minute gaps |
| `deep_work_two_weeks` | 18 | 16 | 5400 / 4020 | Long tasks and 60–120 minute minimum splits |
| `evenings_and_weekends` | 22 | 17 | 2070 / 2520 | Weekday evening and weekend use |

Each workload has a base task-ID assignment, three fixed lowbias32 permutations, and one adversarial assignment. These variants change only which task receives each ID. `representative` runs the six base cases; `permutation` runs all 30 variants. `full` includes only the base cases so repeated workloads do not distort its aggregate results.

## Oracles

Run and summarize the oracle suite without a baseline:

```sh
scripts/benchmark_scheduling.sh oracle > oracle.psv
scripts/compare_scheduling_quality.sh oracle.psv
```

Tiny cases use a live exhaustive minute-level search. Medium cases use inputs from `benchmark/oracles/medium-cases-v1.json` and cached CP-SAT results from `benchmark/oracles/medium-results-v1.json`. Normal tests and benchmarks do not require Python or OR-Tools.

After intentionally changing the medium cases or offline model, regenerate the cached results:

```sh
scripts/generate_scheduling_oracles.sh
```

Regeneration requires `uv` and Python 3.12. The OR-Tools version is pinned in `tools/scheduling_oracle/requirements.txt`; results are written only when every solve reports an optimum.
