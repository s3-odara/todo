import gleam/float
import gleam/int
import gleam/list
import gleam/order
import tasks/domain/policy
import tasks/domain/scheduling/model.{
  type ScheduleBlock, type SchedulingTask, type Score, Score,
}

pub const epsilon = 0.000000000001

const gauss_node = 0.7745966692414834

pub type Contribution {
  Contribution(task_id: Int, score: Score)
}

type IntegrationState {
  IntegrationState(
    previous_end_seconds: Int,
    completed_seconds: Float,
    accumulated_error: Float,
  )
}

pub fn evaluate(
  tasks: List(SchedulingTask),
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Score {
  contributions(tasks, blocks, planning_start)
  |> total
}

pub fn contributions(
  tasks: List(SchedulingTask),
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> List(Contribution) {
  list.map(tasks, fn(task) {
    let own = list.filter(blocks, fn(block) { block.task_id == task.id })
    Contribution(task.id, evaluate_task(task, own, planning_start))
  })
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

/// Replace one task's contribution in an aggregate without summing every task.
/// Float addition order may change, but candidate ordering tolerates that drift.
pub fn replace_total(
  total: Score,
  previous: Score,
  replacement: Score,
) -> Score {
  Score(
    total.weighted_unscheduled_minutes
      - previous.weighted_unscheduled_minutes
      + replacement.weighted_unscheduled_minutes,
    total.weighted_policy_error
      -. previous.weighted_policy_error
      +. replacement.weighted_policy_error,
  )
}

/// Score one task from only that task's canonical blocks.
pub fn evaluate_task(
  task: SchedulingTask,
  own_blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Score {
  let weight = priority_weight(task.priority)
  Score(
    weight * int.max(0, task.estimate_minutes - placed_minutes(own_blocks)),
    int.to_float(weight)
      *. policy_error_for_blocks(task, own_blocks, planning_start),
  )
}

/// Integrate squared policy error from one task's canonical blocks.
///
/// Blocks must be non-overlapping and within the planning window.
/// Scheduling boundaries enforce this once; score evaluation stays O(B).
pub fn policy_error(
  task: SchedulingTask,
  own_blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Float {
  policy_error_for_blocks(task, own_blocks, planning_start)
}

fn policy_error_for_blocks(
  task: SchedulingTask,
  blocks: List(ScheduleBlock),
  planning_start: Int,
) -> Float {
  case task.estimate_minutes > 0 && task.deadline_seconds > planning_start {
    False -> 0.0
    True -> {
      let span = int.to_float(task.deadline_seconds - planning_start)
      let estimate = int.to_float(task.estimate_minutes * 60)
      integrate_blocks(
        task.scheduling_policy,
        blocks,
        planning_start,
        span,
        estimate,
      )
    }
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
) -> Float {
  let initial = IntegrationState(planning_start, 0.0, 0.0)
  let final =
    list.fold(blocks, initial, fn(state, block) {
      let IntegrationState(previous_end, completed, error) = state
      let start = block.start_seconds
      let end = block.end_seconds
      let gap_start = normalized(previous_end, planning_start, span)
      let block_start = normalized(start, planning_start, span)
      let block_end = normalized(end, planning_start, span)
      let progress = completed /. estimate
      let gap_error =
        integrate_segment(policy, gap_start, block_start, progress, 0.0)
      let work_error =
        integrate_segment(
          policy,
          block_start,
          block_end,
          progress,
          span /. estimate,
        )
      IntegrationState(
        end,
        completed +. int.to_float(end - start),
        { error +. gap_error } +. work_error,
      )
    })
  final.accumulated_error
  +. integrate_segment(
    policy,
    normalized(final.previous_end_seconds, planning_start, span),
    1.0,
    final.completed_seconds /. estimate,
    0.0,
  )
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
  let difference = actual -. policy.value(policy, x)
  difference *. difference
}

/// Sum minutes from blocks already projected to one task.
pub fn placed_minutes(blocks: List(ScheduleBlock)) -> Int {
  list.fold(blocks, 0, fn(total, block) {
    total + { block.end_seconds - block.start_seconds } / 60
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

/// Total ordering used to rank candidates deterministically.
///
/// Epsilon is deliberately excluded because approximate equality is not
/// transitive and therefore cannot define a total ordering.
pub fn compare(a: Score, b: Score) -> order.Order {
  case
    int.compare(a.weighted_unscheduled_minutes, b.weighted_unscheduled_minutes)
  {
    order.Eq -> float.compare(a.weighted_policy_error, b.weighted_policy_error)
    other -> other
  }
}

/// Require a meaningful improvement while keeping candidate ranking total.
pub fn strictly_better(a: Score, than b: Score) -> Bool {
  case
    int.compare(a.weighted_unscheduled_minutes, b.weighted_unscheduled_minutes)
  {
    order.Lt -> True
    order.Gt -> False
    order.Eq -> {
      let difference = a.weighted_policy_error -. b.weighted_policy_error
      difference <. { 0.0 -. epsilon }
    }
  }
}
