import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/time/timestamp
import tasks/domain/due
import tasks/domain/model as task_model
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{type AbsoluteInterval, AbsoluteInterval}

pub const candidate_limit = 20_000

type Candidate {
  Candidate(
    block: scheduling_model.ScheduleBlock,
    score: scheduling_model.Score,
  )
}

pub type RebuildResult {
  RebuildResult(
    blocks: List(scheduling_model.ScheduleBlock),
    contributions: List(score.Contribution),
  )
}

type PlacementResult {
  PlacementResult(
    blocks: List(scheduling_model.ScheduleBlock),
    score: scheduling_model.Score,
  )
}

pub fn build(
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> List(scheduling_model.ScheduleBlock) {
  tasks
  |> initial_order
  |> list.fold([], fn(blocks, task) {
    place_task(blocks, task, projected, planning_start, offset).blocks
  })
}

pub fn rebuild(
  blocks: List(scheduling_model.ScheduleBlock),
  selected: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> RebuildResult {
  let selected_ids = list.map(selected, fn(task) { task.id })
  let base =
    blocks
    |> list.filter(fn(block) { !list.contains(selected_ids, block.task_id) })
    |> invariant.canonicalize
  let #(rebuilt, contributions) =
    list.fold(selected, #(base, []), fn(state, task) {
      let #(current, contributions) = state
      let placed = place_task(current, task, projected, planning_start, offset)
      #(placed.blocks, [
        score.Contribution(task.id, placed.score),
        ..contributions
      ])
    })
  RebuildResult(rebuilt, list.reverse(contributions))
}

pub fn initial_order(tasks: List(task_model.Todo)) -> List(task_model.Todo) {
  list.sort(tasks, by: task_compare)
}

fn place_task(
  blocks: List(scheduling_model.ScheduleBlock),
  task: task_model.Todo,
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> PlacementResult {
  let bounded_candidates =
    placement_candidates(blocks, task, projected, planning_start, offset)
    |> list.take(candidate_limit)
  let own =
    blocks
    |> list.filter(fn(existing) { existing.task_id == task.id })
  let candidates =
    bounded_candidates
    |> maximum_duration_candidates
    |> list.map(fn(block) {
      let next_own = invariant.canonicalize([block, ..own])
      // Other tasks are identical across these candidates, so their scores cancel.
      Candidate(block, score.evaluate_task(task, next_own, planning_start))
    })
  case best(candidates) {
    option.None ->
      PlacementResult(blocks, score.evaluate_task(task, blocks, planning_start))
    option.Some(candidate) -> {
      let next = invariant.canonicalize([candidate.block, ..blocks])
      place_task(next, task, projected, planning_start, offset)
    }
  }
}

fn placement_candidates(
  blocks: List(scheduling_model.ScheduleBlock),
  task: task_model.Todo,
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> List(scheduling_model.ScheduleBlock) {
  let placed = score.placed_minutes(task.id, blocks)
  let remaining = task.estimate_minutes - placed
  case task.due, remaining <= 0 {
    _, True -> []
    option.None, _ -> []
    option.Some(deadline), False -> {
      let due_seconds = due.to_unix_seconds(deadline)
      timeline.free_intervals(projected, blocks)
      |> list.flat_map(fn(interval) {
        let clipped =
          AbsoluteInterval(interval.start, int.min(interval.end, due_seconds))
        let capacity = { clipped.end - clipped.start } / 60
        case capacity <= 0 {
          True -> []
          False -> {
            candidate_lengths(task, remaining, capacity)
            |> list.flat_map(fn(minutes) {
              anchors(task, placed, clipped, minutes, planning_start, offset)
              |> list.map(fn(start) {
                scheduling_model.ScheduleBlock(
                  task.id,
                  timestamp.from_unix_seconds(start),
                  timestamp.from_unix_seconds(start + minutes * 60),
                )
              })
            })
          }
        }
      })
    }
  }
}

fn candidate_lengths(task, remaining, capacity) -> List(Int) {
  let minimum = effective_minimum(task)
  [minimum, int.min(remaining, capacity), remaining - minimum]
  |> unique_ints
  |> list.filter(fn(value) {
    value >= minimum && value <= remaining && value <= capacity
  })
}

fn anchors(
  task: task_model.Todo,
  placed: Int,
  interval: AbsoluteInterval,
  block_length: Int,
  planning_start: Int,
  offset: Int,
) -> List(Int) {
  let estimate = int.to_float(task.estimate_minutes)
  let y0 = int.to_float(placed) /. estimate
  let y1 = int.to_float(placed + block_length) /. estimate
  let due_seconds = case task.due {
    option.Some(value) -> due.to_unix_seconds(value)
    option.None -> interval.end
  }
  let span = int.to_float(due_seconds - planning_start)
  let ideal_start =
    int.to_float(planning_start) +. inverse(task.scheduling_policy, y0) *. span
  let ideal_end =
    int.to_float(planning_start) +. inverse(task.scheduling_policy, y1) *. span
  [
    interval.start,
    interval.end - block_length * 60,
    rounded_local(ideal_start, offset),
    rounded_local(ideal_end, offset) - block_length * 60,
  ]
  |> list.map(fn(start) {
    int.max(interval.start, int.min(start, interval.end - block_length * 60))
  })
  |> unique_ints
}

fn maximum_duration_candidates(
  candidates: List(scheduling_model.ScheduleBlock),
) -> List(scheduling_model.ScheduleBlock) {
  let maximum =
    list.fold(candidates, 0, fn(maximum, block) {
      int.max(maximum, block_duration(block))
    })
  list.filter(candidates, fn(block) { block_duration(block) == maximum })
}

fn block_duration(block: scheduling_model.ScheduleBlock) -> Int {
  invariant.seconds(block.end) - invariant.seconds(block.start)
}

fn best(candidates: List(Candidate)) -> option.Option(Candidate) {
  list.fold(candidates, option.None, fn(current, candidate) {
    case current {
      option.None -> option.Some(candidate)
      option.Some(Candidate(block: existing_block, score: existing_score)) ->
        case score.compare(candidate.score, existing_score) {
          score.Better -> option.Some(candidate)
          score.Worse -> current
          score.Equal ->
            case invariant.block_key_compare(candidate.block, existing_block) {
              order.Lt -> option.Some(candidate)
              _ -> current
            }
        }
    }
  })
}

fn task_compare(a: task_model.Todo, b: task_model.Todo) -> order.Order {
  case int.compare(b.priority, a.priority) {
    order.Eq ->
      case int.compare(due_seconds(a), due_seconds(b)) {
        order.Eq -> int.compare(a.id, b.id)
        other -> other
      }
    other -> other
  }
}

fn due_seconds(task: task_model.Todo) -> Int {
  case task.due {
    option.Some(value) -> due.to_unix_seconds(value)
    option.None -> 0
  }
}

fn inverse(policy, y) {
  let bounded = float.max(0.0, float.min(1.0, y))
  case policy {
    Asap ->
      case float.square_root(1.0 -. bounded) {
        Ok(root) -> 1.0 -. root
        Error(_) -> 0.0
      }
    Spread -> bounded
    NearDeadline ->
      case float.square_root(bounded) {
        Ok(root) -> root
        Error(_) -> 0.0
      }
  }
}

fn rounded_local(value, offset) {
  float.round({ value +. int.to_float(offset) } /. 60.0) * 60 - offset
}

fn effective_minimum(task: task_model.Todo) -> Int {
  case task.estimate_minutes < task.minimum_split_minutes {
    True -> task.estimate_minutes
    False -> task.minimum_split_minutes
  }
}

fn unique_ints(values: List(Int)) -> List(Int) {
  list.fold(values, [], fn(acc, value) {
    case list.contains(acc, value) {
      True -> acc
      False -> [value, ..acc]
    }
  })
  |> list.reverse
}
