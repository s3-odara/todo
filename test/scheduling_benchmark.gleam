import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import scheduling_benchmark_hash.{sample}
import scheduling_fixture
import scheduling_oracle_fixture
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/hill_climb
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{
  type AbsoluteInterval, AbsoluteInterval, SearchSpace,
}

@external(erlang, "scheduling_benchmark_ffi", "monotonic_microseconds")
fn monotonic_microseconds() -> Int

const representative_fixture_path = "benchmark/fixtures/representative-workloads-v1.json"

const medium_oracle_cases_path = "benchmark/oracles/medium-cases-v1.json"

const medium_oracle_results_path = "benchmark/oracles/medium-results-v1.json"

type Profile {
  Underloaded
  Balanced
  OverloadedPriority
  Fragmented
  TightDeadlines
  MinimumSplitTraps
}

type FixtureSelection {
  RepresentativeBase
  IdPermutations
  AllRepresentativeIds
}

type Oracle {
  NoOracle
  ExhaustiveOracle(horizon: Int)
  CachedOracle(score: scheduling_model.Score)
}

type Scenario {
  Scenario(
    name: String,
    tasks: List(scheduling_model.SchedulingTask),
    projected: List(AbsoluteInterval),
    oracle: Oracle,
  )
}

type PriorityMinutes {
  PriorityMinutes(p1: Int, p2: Int, p3: Int, p4: Int, p5: Int)
}

pub fn main() {
  let selected = case argv.load().arguments {
    [] | ["quick"] ->
      list.append(
        focused_scenarios(),
        profile_scenarios_for_sizes([101], [4, 8]),
      )
    ["full"] -> full_scenarios()
    ["holdout"] -> holdout_scenarios()
    ["oracle"] -> oracle_scenarios()
    ["stress"] -> stress_scenarios()
    ["representative"] -> representative_scenarios(RepresentativeBase)
    ["permutation"] -> representative_scenarios(AllRepresentativeIds)
    ["all"] ->
      full_scenarios()
      |> list.append(holdout_scenarios())
      |> list.append(oracle_scenarios())
      |> list.append(representative_scenarios(IdPermutations))
    _ -> {
      io.println(
        "usage: scheduling_benchmark [quick|full|holdout|oracle|stress|representative|permutation|all]",
      )
      []
    }
  }
  io.println(
    "scenario|weighted_estimate|estimate_p1|estimate_p2|estimate_p3|estimate_p4|estimate_p5|initial_unscheduled|initial_policy_error|final_unscheduled|final_policy_error|final_unscheduled_p1|final_unscheduled_p2|final_unscheduled_p3|final_unscheduled_p4|final_unscheduled_p5|oracle_unscheduled|oracle_policy_error|primary_regret|policy_regret|tasks|projected_intervals|initial_blocks|final_blocks|accepted_moves|greedy_us|hill_climb_us|valid",
  )
  selected
  |> list.each(run)
}

fn run(scenario: Scenario) {
  let Scenario(name, tasks, projected, oracle) = scenario
  // One timing preserves a useful diagnostic without making deterministic quality
  // cases five times slower. Runtime is not used to rank solution quality.
  let space = SearchSpace(projected, 0, 0)
  let greedy_started = monotonic_microseconds()
  let initial = greedy.build(tasks, space)
  let greedy_elapsed = monotonic_microseconds() - greedy_started
  let hill_started = monotonic_microseconds()
  let result = hill_climb.improve(initial, tasks, space)
  let hill_elapsed = monotonic_microseconds() - hill_started
  let initial_value = score.evaluate(tasks, initial, 0)
  let value = score.evaluate(tasks, result.blocks, 0)
  let estimates = priority_estimates(tasks)
  let final_unscheduled = priority_unscheduled(tasks, result.blocks)
  let oracle = case oracle {
    NoOracle -> None
    ExhaustiveOracle(horizon) -> exact_optimum(tasks, projected, horizon)
    CachedOracle(score) -> Some(score)
  }
  let valid = case invariant.validate_generation(result.blocks, tasks, space) {
    Ok(_) -> "true"
    Error(_) -> "false"
  }
  let #(oracle_unscheduled, oracle_policy, primary_regret, policy_regret) =
    oracle_columns(value, oracle)
  [
    [name, int.to_string(weighted_estimate(estimates))],
    priority_values(estimates),
    [
      int.to_string(initial_value.weighted_unscheduled_minutes),
      float.to_string(initial_value.weighted_policy_error),
      int.to_string(value.weighted_unscheduled_minutes),
      float.to_string(value.weighted_policy_error),
    ],
    priority_values(final_unscheduled),
    [
      oracle_unscheduled,
      oracle_policy,
      primary_regret,
      policy_regret,
      int.to_string(list.length(tasks)),
      int.to_string(list.length(projected)),
      int.to_string(list.length(initial)),
      int.to_string(list.length(result.blocks)),
      int.to_string(result.accepted_moves),
      int.to_string(greedy_elapsed),
      int.to_string(hill_elapsed),
      valid,
    ],
  ]
  |> list.flatten
  |> string.join("|")
  |> io.println
}

fn priority_estimates(tasks: List(scheduling_model.SchedulingTask)) {
  list.fold(tasks, PriorityMinutes(0, 0, 0, 0, 0), fn(totals, task) {
    add_priority_minutes(totals, task.priority, task.estimate_minutes)
  })
}

fn priority_unscheduled(
  tasks: List(scheduling_model.SchedulingTask),
  blocks: List(scheduling_model.ScheduleBlock),
) {
  list.fold(tasks, PriorityMinutes(0, 0, 0, 0, 0), fn(totals, task) {
    let own = list.filter(blocks, fn(block) { block.task_id == task.id })
    let unscheduled =
      int.max(0, task.estimate_minutes - score.placed_minutes(own))
    add_priority_minutes(totals, task.priority, unscheduled)
  })
}

fn add_priority_minutes(totals: PriorityMinutes, priority: Int, minutes: Int) {
  case totals, priority {
    PriorityMinutes(p1, p2, p3, p4, p5), 1 ->
      PriorityMinutes(p1 + minutes, p2, p3, p4, p5)
    PriorityMinutes(p1, p2, p3, p4, p5), 2 ->
      PriorityMinutes(p1, p2 + minutes, p3, p4, p5)
    PriorityMinutes(p1, p2, p3, p4, p5), 3 ->
      PriorityMinutes(p1, p2, p3 + minutes, p4, p5)
    PriorityMinutes(p1, p2, p3, p4, p5), 4 ->
      PriorityMinutes(p1, p2, p3, p4 + minutes, p5)
    PriorityMinutes(p1, p2, p3, p4, p5), 5 ->
      PriorityMinutes(p1, p2, p3, p4, p5 + minutes)
    _, _ -> totals
  }
}

fn weighted_estimate(minutes: PriorityMinutes) {
  let PriorityMinutes(p1, p2, p3, p4, p5) = minutes
  p1 + p2 * 2 + p3 * 4 + p4 * 8 + p5 * 16
}

fn priority_values(minutes: PriorityMinutes) {
  let PriorityMinutes(p1, p2, p3, p4, p5) = minutes
  [p1, p2, p3, p4, p5] |> list.map(int.to_string)
}

fn oracle_columns(
  value: scheduling_model.Score,
  oracle: Option(scheduling_model.Score),
) {
  case oracle {
    None -> #("-", "-", "-", "-")
    Some(best) -> {
      let primary =
        value.weighted_unscheduled_minutes - best.weighted_unscheduled_minutes
      let policy = case primary == 0 {
        True ->
          float.to_string(
            value.weighted_policy_error -. best.weighted_policy_error,
          )
        False -> "-"
      }
      #(
        int.to_string(best.weighted_unscheduled_minutes),
        float.to_string(best.weighted_policy_error),
        int.to_string(primary),
        policy,
      )
    }
  }
}

fn focused_scenarios() -> List(Scenario) {
  [
    Scenario(
      "short_remainder",
      [task(1, 100, 3, 120, 30, Spread)],
      [interval(0, 80), interval(90, 120)],
      NoOracle,
    ),
    Scenario(
      "priority_contention",
      [
        task(1, 120, 1, 120, 30, Asap),
        task(2, 180, 5, 360, 30, Spread),
        task(3, 90, 4, 240, 30, NearDeadline),
        task(4, 120, 3, 360, 30, Spread),
      ],
      [interval(0, 300)],
      NoOracle,
    ),
    Scenario(
      "fragmented",
      legacy_generated_tasks(8, 0, []),
      [
        interval(0, 45),
        interval(60, 120),
        interval(150, 210),
        interval(240, 300),
        interval(330, 390),
        interval(420, 480),
      ],
      NoOracle,
    ),
    Scenario(
      "mixed_medium",
      legacy_generated_tasks(12, 3, []),
      [interval(0, 240), interval(300, 540), interval(600, 840)],
      NoOracle,
    ),
  ]
}

fn legacy_generated_tasks(
  count: Int,
  salt: Int,
  acc: List(scheduling_model.SchedulingTask),
) -> List(scheduling_model.SchedulingTask) {
  case count {
    0 -> list.reverse(acc)
    id -> {
      let estimate = 30 + { id * 37 + salt * 11 } % 121
      let priority = 1 + { id * 3 + salt } % 5
      let deadline = 180 + { id * 97 + salt * 53 } % 661
      let minimum = case { id + salt } % 3 {
        0 -> 15
        1 -> 30
        _ -> 45
      }
      let policy = case { id * 2 + salt } % 3 {
        0 -> Asap
        1 -> Spread
        _ -> NearDeadline
      }
      legacy_generated_tasks(count - 1, salt, [
        task(id, estimate, priority, deadline, minimum, policy),
        ..acc
      ])
    }
  }
}

fn representative_scenarios(selection: FixtureSelection) -> List(Scenario) {
  let scheduling_fixture.FixtureCorpus(base, permutations) = case
    scheduling_fixture.load(representative_fixture_path)
  {
    Ok(corpus) -> corpus
    Error(error) -> panic as error
  }
  let selected = case selection {
    RepresentativeBase -> base
    IdPermutations -> permutations
    AllRepresentativeIds -> list.append(base, permutations)
  }
  list.map(selected, fn(scenario) {
    let scheduling_fixture.FixtureScenario(name, tasks, projected) = scenario
    Scenario(name, tasks, projected, NoOracle)
  })
}

fn full_scenarios() -> List(Scenario) {
  focused_scenarios()
  |> list.append(
    profile_scenarios_for_sizes([101, 211, 307, 401, 503], [4, 8, 12, 16]),
  )
  |> list.append(profile_scenarios_for_sizes([101, 211, 307], [24, 27, 28, 32]))
  |> list.append(profile_scenarios_for_sizes([7001], [64]))
  // Large coverage uses multiple seeds rather than an implementation-specific
  // 141/142 candidate-composition boundary that may move with the algorithm.
  |> list.append(
    profile_scenarios([Balanced, Fragmented, MinimumSplitTraps], [7001, 7013], [
      128,
    ]),
  )
  |> list.append(representative_scenarios(RepresentativeBase))
}

fn holdout_scenarios() -> List(Scenario) {
  profile_scenarios_for_sizes([9001, 9011, 9029, 9041, 9059], [4, 8, 12, 16])
  // One distinct seed per size detects boundary-specific regressions without
  // multiplying the cost of this validation-only suite.
  |> list.append(profile_scenarios_for_sizes([9001], [24]))
  |> list.append(profile_scenarios_for_sizes([9011], [28]))
  |> list.append(profile_scenarios_for_sizes([9029], [32]))
  |> list.append(profile_scenarios_for_sizes([9041], [64]))
  |> list.append(
    profile_scenarios([Balanced, Fragmented, MinimumSplitTraps], [9041, 9059], [
      128,
    ]),
  )
}

fn profile_scenarios_for_sizes(
  seeds: List(Int),
  sizes: List(Int),
) -> List(Scenario) {
  profile_scenarios(profiles(), seeds, sizes)
}

fn profile_scenarios(
  selected_profiles: List(Profile),
  seeds: List(Int),
  sizes: List(Int),
) -> List(Scenario) {
  selected_profiles
  |> list.flat_map(fn(profile) {
    sizes
    |> list.flat_map(fn(count) {
      seeds
      |> list.map(fn(seed) { profile_scenario(profile, count, seed) })
    })
  })
}

fn stress_scenarios() -> List(Scenario) {
  profiles()
  |> list.flat_map(fn(profile) {
    [32, 64, 128, 141, 142, 143]
    |> list.map(fn(count) { profile_scenario(profile, count, 7001) })
  })
}

fn profiles() -> List(Profile) {
  [
    Underloaded,
    Balanced,
    OverloadedPriority,
    Fragmented,
    TightDeadlines,
    MinimumSplitTraps,
  ]
}

fn profile_scenario(profile, count, seed) -> Scenario {
  let #(projected, horizon) = profile_timeline(profile, count)
  let name =
    profile_name(profile)
    <> "_n"
    <> int.to_string(count)
    <> "_s"
    <> int.to_string(seed)
  Scenario(
    name,
    generated_tasks(profile, count, seed, horizon),
    projected,
    NoOracle,
  )
}

fn profile_name(profile: Profile) -> String {
  case profile {
    Underloaded -> "underloaded_mixed"
    Balanced -> "balanced_contention"
    OverloadedPriority -> "overloaded_priority"
    Fragmented -> "fragmented_availability"
    TightDeadlines -> "tight_deadlines"
    MinimumSplitTraps -> "minimum_split_traps"
  }
}

fn profile_timeline(profile: Profile, count: Int) {
  case profile {
    Underloaded -> {
      let horizon = count * 110
      #([interval(0, horizon)], horizon)
    }
    Balanced -> {
      let horizon = count * 60
      #([interval(0, horizon)], horizon)
    }
    OverloadedPriority -> {
      let horizon = count * 35
      #([interval(0, horizon)], horizon)
    }
    Fragmented -> {
      let projected = repeated_intervals(count, 0, 45, 15, [])
      #(projected, count * 60)
    }
    TightDeadlines -> {
      let horizon = count * 65
      #([interval(0, horizon)], horizon)
    }
    MinimumSplitTraps -> {
      let projected = repeated_intervals(count, 0, 40, 20, [])
      #(projected, count * 60)
    }
  }
}

fn repeated_intervals(count, start, length, gap, acc) {
  case count {
    0 -> list.reverse(acc)
    _ ->
      repeated_intervals(count - 1, start + length + gap, length, gap, [
        interval(start, start + length),
        ..acc
      ])
  }
}

fn generated_tasks(
  profile,
  count,
  seed,
  horizon,
) -> List(scheduling_model.SchedulingTask) {
  generated_tasks_loop(profile, count, seed, horizon, [])
}

fn generated_tasks_loop(profile, remaining, seed, horizon, acc) {
  case remaining {
    0 -> acc
    index -> {
      let estimate = case profile {
        Underloaded -> 30 + sample(seed, index * 11 + 1, 61)
        MinimumSplitTraps -> 45 + sample(seed, index * 11 + 1, 61)
        _ -> 30 + sample(seed, index * 11 + 1, 91)
      }
      let priority = 1 + sample(seed, index * 11 + 2, 5)
      let deadline = task_deadline(profile, seed, index, horizon)
      let proposed_minimum = case profile {
        MinimumSplitTraps ->
          [30, 40, 45, 60]
          |> list.drop(sample(seed, index * 11 + 3, 4))
          |> first_or(30)
        _ ->
          [15, 30, 45]
          |> list.drop(sample(seed, index * 11 + 3, 3))
          |> first_or(15)
      }
      let minimum = int.min(estimate, proposed_minimum)
      let policy = case sample(seed, index * 11 + 4, 3) {
        0 -> Asap
        1 -> Spread
        _ -> NearDeadline
      }
      // IDs deliberately vary independently of input order; otherwise tuning can
      // accidentally reward one deterministic tie-break pattern.
      let id = seed * 10_000 + { index * 7919 + seed } % 9973 + 1
      generated_tasks_loop(profile, remaining - 1, seed, horizon, [
        task(id, estimate, priority, deadline, minimum, policy),
        ..acc
      ])
    }
  }
}

fn task_deadline(profile, seed, index, horizon) -> Int {
  case profile {
    Underloaded ->
      int.max(
        1,
        horizon * 3 / 4 + sample(seed, index * 13 + 5, int.max(1, horizon / 4)),
      )
    TightDeadlines ->
      int.max(
        1,
        horizon / 6 + sample(seed, index * 13 + 5, int.max(1, horizon * 2 / 3)),
      )
    _ -> 1 + sample(seed, index * 13 + 5, int.max(1, horizon))
  }
}

fn first_or(values: List(Int), fallback: Int) -> Int {
  case values {
    [first, ..] -> first
    [] -> fallback
  }
}

fn exact_scenarios() -> List(Scenario) {
  int.range(from: 1, to: 31, with: [], run: fn(scenarios, seed) {
    [exact_scenario(seed), ..scenarios]
  })
  |> list.reverse
}

fn exact_scenario(seed: Int) -> Scenario {
  let horizon = 8
  let projected = case seed % 3 {
    0 -> [interval(0, 3), interval(4, 8)]
    1 -> [interval(0, 8)]
    _ -> [interval(0, 2), interval(3, 5), interval(6, 8)]
  }
  let tasks =
    [1, 2, 3]
    |> list.map(fn(id) {
      let estimate = 2 + sample(seed, id * 17, 4)
      let priority = 1 + sample(seed, id * 17 + 1, 5)
      let deadline = 3 + sample(seed, id * 17 + 2, 6)
      let minimum = 1 + sample(seed, id * 17 + 3, int.min(2, estimate))
      let policy = case sample(seed, id * 17 + 4, 3) {
        0 -> Asap
        1 -> Spread
        _ -> NearDeadline
      }
      task(id, estimate, priority, deadline, minimum, policy)
    })
  Scenario(
    "exact_s" <> int.to_string(seed),
    tasks,
    projected,
    ExhaustiveOracle(horizon),
  )
}

fn oracle_scenarios() {
  list.append(exact_scenarios(), medium_oracle_scenarios())
}

fn medium_oracle_scenarios() -> List(Scenario) {
  let scenarios = case
    scheduling_oracle_fixture.load(
      medium_oracle_cases_path,
      medium_oracle_results_path,
    )
  {
    Ok(scenarios) -> scenarios
    Error(error) -> panic as error
  }
  list.map(scenarios, fn(scenario) {
    let scheduling_oracle_fixture.OracleScenario(
      name,
      tasks,
      projected,
      witness,
    ) = scenario
    Scenario(
      name,
      tasks,
      projected,
      CachedOracle(score.evaluate(tasks, witness, 0)),
    )
  })
}

fn exact_optimum(
  tasks: List(scheduling_model.SchedulingTask),
  projected: List(AbsoluteInterval),
  horizon: Int,
) -> Option(scheduling_model.Score) {
  // Enumerating every minute assignment is intentionally independent of the
  // production candidate generator, so it can expose local-search blind spots.
  let choices = [0, ..list.map(tasks, fn(task) { task.id })]
  exact_assignments(choices, horizon, [], tasks, projected, None)
}

fn exact_assignments(
  choices: List(Int),
  remaining: Int,
  assignment: List(Int),
  tasks: List(scheduling_model.SchedulingTask),
  projected: List(AbsoluteInterval),
  best: Option(scheduling_model.Score),
) -> Option(scheduling_model.Score) {
  case remaining {
    0 -> {
      let blocks =
        assignment
        |> list.reverse
        |> assignment_blocks(0, [])
        |> invariant.canonicalize
      case
        invariant.validate_generation(
          blocks,
          tasks,
          SearchSpace(projected, 0, 0),
        )
      {
        Error(_) -> best
        Ok(_) -> choose_score(best, score.evaluate(tasks, blocks, 0))
      }
    }
    _ ->
      list.fold(choices, best, fn(current, choice) {
        exact_assignments(
          choices,
          remaining - 1,
          [choice, ..assignment],
          tasks,
          projected,
          current,
        )
      })
  }
}

fn assignment_blocks(
  values: List(Int),
  minute: Int,
  acc: List(scheduling_model.ScheduleBlock),
) {
  case values {
    [] -> acc
    [0, ..rest] -> assignment_blocks(rest, minute + 1, acc)
    [task_id, ..rest] ->
      assignment_blocks(rest, minute + 1, [
        scheduling_model.ScheduleBlock(
          task_id,
          minute * 60,
          { minute + 1 } * 60,
        ),
        ..acc
      ])
  }
}

fn choose_score(
  current: Option(scheduling_model.Score),
  candidate: scheduling_model.Score,
) -> Option(scheduling_model.Score) {
  case current {
    None -> Some(candidate)
    Some(existing) ->
      case score.compare(candidate, existing) {
        order.Lt -> Some(candidate)
        order.Eq | order.Gt -> current
      }
  }
}

fn task(id, estimate, priority, deadline, minimum, policy) {
  scheduling_model.SchedulingTask(
    id,
    estimate,
    priority,
    deadline * 60,
    policy,
    minimum,
  )
}

fn interval(start, end) {
  AbsoluteInterval(start * 60, end * 60)
}
