import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import tasks/domain/due
import tasks/domain/model.{type Todo, Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/hill_climb
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{type AbsoluteInterval, AbsoluteInterval}

@external(erlang, "scheduling_benchmark_ffi", "monotonic_microseconds")
fn monotonic_microseconds() -> Int

type Scenario {
  Scenario(name: String, tasks: List(Todo), projected: List(AbsoluteInterval))
}

pub fn main() {
  io.println(
    "scenario|initial_unscheduled|initial_policy_error|final_unscheduled|final_policy_error|blocks|accepted_moves|greedy_us|hill_climb_us|valid",
  )
  scenarios()
  |> list.each(run)
}

fn run(scenario: Scenario) {
  let Scenario(name, tasks, projected) = scenario
  // Warm once, then average fixed repetitions so revisions remain comparable.
  let _ = search(tasks, projected)
  let greedy_started = monotonic_microseconds()
  let _ = greedy.build(tasks, projected, 0, 0)
  let _ = greedy.build(tasks, projected, 0, 0)
  let _ = greedy.build(tasks, projected, 0, 0)
  let _ = greedy.build(tasks, projected, 0, 0)
  let initial = greedy.build(tasks, projected, 0, 0)
  let greedy_elapsed = { monotonic_microseconds() - greedy_started } / 5
  let hill_started = monotonic_microseconds()
  let _ = hill_climb.climb(initial, tasks, projected, 0, 0)
  let _ = hill_climb.climb(initial, tasks, projected, 0, 0)
  let _ = hill_climb.climb(initial, tasks, projected, 0, 0)
  let _ = hill_climb.climb(initial, tasks, projected, 0, 0)
  let result = hill_climb.climb(initial, tasks, projected, 0, 0)
  let hill_elapsed = { monotonic_microseconds() - hill_started } / 5
  let initial_value = score.evaluate(tasks, initial, 0)
  let value = score.evaluate(tasks, result.blocks, 0)
  let valid = case
    invariant.validate_generation(result.blocks, tasks, projected, 0, 0)
  {
    Ok(_) -> "true"
    Error(_) -> "false"
  }
  io.println(
    name
    <> "|"
    <> int.to_string(initial_value.weighted_unscheduled_minutes)
    <> "|"
    <> float.to_string(initial_value.weighted_policy_error)
    <> "|"
    <> int.to_string(value.weighted_unscheduled_minutes)
    <> "|"
    <> float.to_string(value.weighted_policy_error)
    <> "|"
    <> int.to_string(list.length(result.blocks))
    <> "|"
    <> int.to_string(result.accepted_moves)
    <> "|"
    <> int.to_string(greedy_elapsed)
    <> "|"
    <> int.to_string(hill_elapsed)
    <> "|"
    <> valid,
  )
}

fn search(tasks, projected) {
  let initial = greedy.build(tasks, projected, 0, 0)
  hill_climb.climb(initial, tasks, projected, 0, 0)
}

fn scenarios() -> List(Scenario) {
  let focused = [
    Scenario("short_remainder", [task(1, 100, 3, 120, 30, Spread)], [
      interval(0, 80),
      interval(90, 120),
    ]),
    Scenario(
      "priority_contention",
      [
        task(1, 120, 1, 120, 30, Asap),
        task(2, 180, 5, 360, 30, Spread),
        task(3, 90, 4, 240, 30, NearDeadline),
        task(4, 120, 3, 360, 30, Spread),
      ],
      [interval(0, 300)],
    ),
    Scenario("fragmented", generated_tasks(8, 0, []), [
      interval(0, 45),
      interval(60, 120),
      interval(150, 210),
      interval(240, 300),
      interval(330, 390),
      interval(420, 480),
    ]),
    Scenario("mixed_medium", generated_tasks(12, 3, []), [
      interval(0, 240),
      interval(300, 540),
      interval(600, 840),
    ]),
  ]
  list.append(
    focused,
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
      |> list.map(generated_scenario),
  )
}

fn generated_scenario(salt: Int) -> Scenario {
  let projected = case salt % 2 {
    0 -> [interval(0, 240), interval(300, 540)]
    _ -> [
      interval(0, 45),
      interval(60, 120),
      interval(150, 210),
      interval(240, 300),
      interval(330, 390),
      interval(420, 480),
    ]
  }
  Scenario(
    "generated_" <> int.to_string(salt),
    generated_tasks(8, salt, []),
    projected,
  )
}

fn generated_tasks(count: Int, salt: Int, acc: List(Todo)) -> List(Todo) {
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
      generated_tasks(count - 1, salt, [
        task(id, estimate, priority, deadline, minimum, policy),
        ..acc
      ])
    }
  }
}

fn task(id, estimate, priority, deadline, minimum, policy) {
  Todo(
    id,
    "task " <> int.to_string(id),
    estimate,
    priority,
    Some(due.from_unix_seconds(deadline * 60)),
    Pending,
    policy,
    minimum,
  )
}

fn interval(start, end) {
  AbsoluteInterval(start * 60, end * 60)
}
