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

const gauss_node = 0.7745966692414834

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

/// Integrates squared policy error over normalized calendar progress [0, 1].
///
/// Blocks must be canonical, non-overlapping, and within the planning window.
/// Scheduling boundaries enforce this once; score evaluation stays O(B).
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
      case due_seconds > planning_start {
        False -> 0.0
        True -> {
          let span = int.to_float(due_seconds - planning_start)
          let estimate = int.to_float(task.estimate_minutes * 60)
          integrate_blocks(
            task.scheduling_policy,
            blocks,
            planning_start,
            span,
            estimate,
            planning_start,
            0.0,
            0.0,
          )
        }
      }
    }
    _, _ -> 0.0
  }
}

// Revalidating canonical blocks in this hot path duplicates the invariant
// boundary and would run for every search candidate.
fn integrate_blocks(
  policy,
  blocks: List(ScheduleBlock),
  planning_start: Int,
  span: Float,
  estimate: Float,
  previous_end: Int,
  completed: Float,
  error: Float,
) -> Float {
  case blocks {
    [] ->
      error
      +. integrate_segment(
        policy,
        normalized(previous_end, planning_start, span),
        1.0,
        completed /. estimate,
        0.0,
      )
    [block, ..rest] -> {
      let start = invariant.seconds(block.start)
      let end = invariant.seconds(block.end)
      let gap_start = normalized(previous_end, planning_start, span)
      let block_start = normalized(start, planning_start, span)
      let block_end = normalized(end, planning_start, span)
      let progress = completed /. estimate
      let next_error =
        error
        +. integrate_segment(policy, gap_start, block_start, progress, 0.0)
        +. integrate_segment(
          policy,
          block_start,
          block_end,
          progress,
          span /. estimate,
        )
      integrate_blocks(
        policy,
        rest,
        planning_start,
        span,
        estimate,
        end,
        completed +. int.to_float(end - start),
        next_error,
      )
    }
  }
}

fn normalized(seconds: Int, planning_start: Int, span: Float) -> Float {
  int.to_float(seconds - planning_start) /. span
}

// Three-point Gauss-Legendre is exact here: actual is linear on a segment,
// policy is quadratic, and their squared difference has degree at most four.
fn integrate_segment(
  policy,
  left,
  right,
  progress_left,
  progress_slope,
) -> Float {
  case right <=. left {
    True -> 0.0
    False -> {
      let midpoint = { left +. right } /. 2.0
      let half_width = { right -. left } /. 2.0
      let left_node = midpoint -. half_width *. gauss_node
      let right_node = midpoint +. half_width *. gauss_node
      half_width
      *. {
        5.0
        /. 9.0
        *. squared_error(
          policy,
          left_node,
          progress_left +. { left_node -. left } *. progress_slope,
        )
        +. 8.0
        /. 9.0
        *. squared_error(
          policy,
          midpoint,
          progress_left +. { midpoint -. left } *. progress_slope,
        )
        +. 5.0
        /. 9.0
        *. squared_error(
          policy,
          right_node,
          progress_left +. { right_node -. left } *. progress_slope,
        )
      }
    }
  }
}

fn squared_error(policy, x, actual) -> Float {
  let difference = actual -. policy_value(policy, x)
  difference *. difference
}

pub fn policy_value(policy, x) -> Float {
  case policy {
    Asap -> 1.0 -. { 1.0 -. x } *. { 1.0 -. x }
    Spread -> x
    NearDeadline -> x *. x
  }
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
