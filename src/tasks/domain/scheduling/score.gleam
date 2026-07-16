import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import tasks/domain/due
import tasks/domain/model as task_model
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model.{type ScheduleBlock, type Score, Score}

pub const epsilon = 0.000000000001

pub const sample_count = 256

pub type Comparison {
  Better
  Equal
  Worse
}

pub fn evaluate(
  tasks: List(task_model.Todo),
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Score {
  list.fold(tasks, Score(0, 0.0), fn(score, task) {
    let weight = priority_weight(task.priority)
    let placed = placed_minutes(task.id, blocks)
    Score(
      score.weighted_unscheduled_minutes
        + weight
        * int.max(0, task.estimate_minutes - placed),
      score.weighted_policy_error
        +. int.to_float(weight)
        *. policy_error(task, blocks, planning_start),
    )
  })
}

pub fn policy_error(
  task: task_model.Todo,
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Float {
  case task.due, task.estimate_minutes > 0 {
    option.Some(deadline), True -> {
      let due_seconds = due.to_unix_seconds(deadline)
      let span = int.to_float(due_seconds - planning_start)
      case span >. 0.0 {
        False -> 0.0
        True ->
          sample_sum(task, blocks, planning_start, span, 0, 0.0)
          /. int.to_float(sample_count)
      }
    }
    _, _ -> 0.0
  }
}

fn sample_sum(task, blocks, planning_start, span, k, sum) {
  case k >= sample_count {
    True -> sum
    False -> {
      let x = { int.to_float(k) +. 0.5 } /. int.to_float(sample_count)
      let sample = int.to_float(planning_start) +. x *. span
      let actual = progress(task, blocks, sample)
      let desired = policy_value(task.scheduling_policy, x)
      let difference = actual -. desired
      sample_sum(
        task,
        blocks,
        planning_start,
        span,
        k + 1,
        sum +. difference *. difference,
      )
    }
  }
}

pub fn policy_value(policy, x) -> Float {
  case policy {
    Asap -> 1.0 -. { 1.0 -. x } *. { 1.0 -. x }
    Spread -> x
    NearDeadline -> x *. x
  }
}

fn progress(
  task: task_model.Todo,
  blocks: List(ScheduleBlock),
  sample: Float,
) -> Float {
  let worked_seconds =
    blocks
    |> list.filter(fn(block) { block.task_id == task.id })
    |> list.fold(0.0, fn(total, block) {
      let start = int.to_float(invariant.seconds(block.start))
      let end = int.to_float(invariant.seconds(block.end))
      case sample <=. start {
        True -> total
        False -> total +. float.min(sample, end) -. start
      }
    })
  worked_seconds /. { int.to_float(task.estimate_minutes) *. 60.0 }
}

pub fn placed_minutes(task_id: Int, blocks: List(ScheduleBlock)) -> Int {
  blocks
  |> list.filter(fn(block) { block.task_id == task_id })
  |> list.fold(0, fn(total, block) {
    total
    + { invariant.seconds(block.end) - invariant.seconds(block.start) }
    / 60
  })
}

pub fn priority_weight(priority: Int) -> Int {
  case priority {
    1 -> 1
    2 -> 2
    3 -> 4
    4 -> 8
    5 -> 16
    _ -> 0
  }
}

pub fn compare(a: Score, b: Score) -> Comparison {
  case
    int.compare(a.weighted_unscheduled_minutes, b.weighted_unscheduled_minutes)
  {
    order.Lt -> Better
    order.Gt -> Worse
    order.Eq -> {
      let difference = a.weighted_policy_error -. b.weighted_policy_error
      case float.absolute_value(difference) <=. epsilon {
        True -> Equal
        False ->
          case difference <. 0.0 {
            True -> Better
            False -> Worse
          }
      }
    }
  }
}

pub fn strictly_better(a: Score, than b: Score) -> Bool {
  compare(a, b) == Better
}
