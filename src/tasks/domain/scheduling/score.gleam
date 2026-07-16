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

pub type Contribution {
  Contribution(task_id: Int, score: Score)
}

pub fn evaluate(
  tasks: List(task_model.Todo),
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Score {
  contributions(tasks, blocks, planning_start)
  |> total
}

pub fn contributions(
  tasks: List(task_model.Todo),
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> List(Contribution) {
  list.map(tasks, fn(task) {
    Contribution(task.id, evaluate_task(task, blocks, planning_start))
  })
}

pub fn evaluate_task(
  task: task_model.Todo,
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Score {
  // Filter once: policy sampling must not rescan unrelated blocks 256 times.
  let own = list.filter(blocks, fn(block) { block.task_id == task.id })
  let weight = priority_weight(task.priority)
  Score(
    weight * int.max(0, task.estimate_minutes - placed_minutes_in(own)),
    int.to_float(weight) *. policy_error_for_blocks(task, own, planning_start),
  )
}

pub fn total(values: List(Contribution)) -> Score {
  list.fold(values, Score(0, 0.0), fn(total, contribution) {
    Score(
      total.weighted_unscheduled_minutes
        + contribution.score.weighted_unscheduled_minutes,
      total.weighted_policy_error +. contribution.score.weighted_policy_error,
    )
  })
}

pub fn replace_contributions(
  current: List(Contribution),
  replacements: List(Contribution),
) -> List(Contribution) {
  // Preserve task order so Float addition and deterministic tie-breaking stay stable.
  list.map(current, fn(contribution) { replacement(contribution, replacements) })
}

fn replacement(current: Contribution, replacements: List(Contribution)) {
  case replacements {
    [] -> current
    [candidate, ..rest] ->
      case candidate.task_id == current.task_id {
        True -> candidate
        False -> replacement(current, rest)
      }
  }
}

pub fn policy_error(
  task: task_model.Todo,
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Float {
  let own = list.filter(blocks, fn(block) { block.task_id == task.id })
  policy_error_for_blocks(task, own, planning_start)
}

fn policy_error_for_blocks(
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
        True -> {
          let sum = case sweep_safe(blocks, option.None) {
            True ->
              sample_sum_sweep(task, blocks, planning_start, span, 0, 0.0, 0.0)
            False -> sample_sum(task, blocks, planning_start, span, 0, 0.0)
          }
          sum /. int.to_float(sample_count)
        }
      }
    }
    _, _ -> 0.0
  }
}

fn sweep_safe(
  blocks: List(ScheduleBlock),
  previous_end: option.Option(Int),
) -> Bool {
  case blocks {
    [] -> True
    [block, ..rest] -> {
      let start = invariant.seconds(block.start)
      let end = invariant.seconds(block.end)
      start < end
      && case previous_end {
        option.None -> sweep_safe(rest, option.Some(end))
        option.Some(previous) ->
          start >= previous && sweep_safe(rest, option.Some(end))
      }
    }
  }
}

fn sample_sum_sweep(
  task: task_model.Todo,
  blocks: List(ScheduleBlock),
  planning_start: Int,
  span: Float,
  k: Int,
  sum: Float,
  completed_work: Float,
) -> Float {
  case k >= sample_count {
    True -> sum
    False -> {
      let x = { int.to_float(k) +. 0.5 } /. int.to_float(sample_count)
      let sample = int.to_float(planning_start) +. x *. span
      let #(remaining, completed) =
        advance_completed(blocks, sample, completed_work)
      let worked_seconds = case remaining {
        [] -> completed
        [block, ..] -> {
          let start = int.to_float(invariant.seconds(block.start))
          case sample <=. start {
            True -> completed
            False -> completed +. sample -. start
          }
        }
      }
      let actual =
        worked_seconds /. { int.to_float(task.estimate_minutes) *. 60.0 }
      let desired = policy_value(task.scheduling_policy, x)
      let difference = actual -. desired
      sample_sum_sweep(
        task,
        remaining,
        planning_start,
        span,
        k + 1,
        sum +. difference *. difference,
        completed,
      )
    }
  }
}

fn advance_completed(
  blocks: List(ScheduleBlock),
  sample: Float,
  completed_work: Float,
) -> #(List(ScheduleBlock), Float) {
  case blocks {
    [] -> #(blocks, completed_work)
    [block, ..rest] -> {
      let end = int.to_float(invariant.seconds(block.end))
      case sample >=. end {
        False -> #(blocks, completed_work)
        True -> {
          let start = int.to_float(invariant.seconds(block.start))
          advance_completed(rest, sample, completed_work +. end -. start)
        }
      }
    }
  }
}

// Fallback retains the public API's behavior for arbitrary block lists.
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
    list.fold(blocks, 0.0, fn(total, block) {
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
  |> placed_minutes_in
}

fn placed_minutes_in(blocks: List(ScheduleBlock)) -> Int {
  list.fold(blocks, 0, fn(total, block) {
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
