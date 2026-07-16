import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/time/timestamp
import tasks/domain/due
import tasks/domain/model as task_model
import tasks/domain/scheduling/model.{type ScheduleBlock, ScheduleBlock}
import tasks/domain/scheduling/timeline.{type AbsoluteInterval}

pub type InvariantError {
  InvalidSchedule
}

pub fn canonicalize(blocks: List(ScheduleBlock)) -> List(ScheduleBlock) {
  blocks
  |> list.sort(by: block_compare)
  |> merge_adjacent([])
  |> list.reverse
}

/// Validate a newly generated state against all live scheduling constraints.
pub fn validate_generation(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  utc_offset_seconds: Int,
) -> Result(List(ScheduleBlock), InvariantError) {
  let canonical = canonicalize(blocks)
  case
    blocks == canonical
    && structural(canonical, tasks, utc_offset_seconds)
    && all_after(canonical, planning_start)
    && contained(canonical, projected)
    && task_constraints(tasks, canonical)
  {
    True -> Ok(canonical)
    False -> Error(InvalidSchedule)
  }
}

/// Persisted schedules are snapshots: only structural properties are live.
pub fn validate_persisted(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  utc_offset_seconds: Int,
) -> Result(List(ScheduleBlock), InvariantError) {
  case
    blocks == canonicalize(blocks)
    && structural(blocks, tasks, utc_offset_seconds)
  {
    True -> Ok(blocks)
    False -> Error(InvalidSchedule)
  }
}

fn structural(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  offset: Int,
) -> Bool {
  no_overlap(blocks, option.None)
  && list.all(blocks, fn(block) {
    let start = seconds(block.start)
    let end = seconds(block.end)
    start < end
    && nanoseconds(block.start) == 0
    && nanoseconds(block.end) == 0
    && floor_mod(start + offset, 60) == 0
    && floor_mod(end + offset, 60) == 0
    && has_task(tasks, block.task_id)
  })
}

fn all_after(blocks: List(ScheduleBlock), planning_start: Int) -> Bool {
  list.all(blocks, fn(block) { seconds(block.start) >= planning_start })
}

fn contained(
  blocks: List(ScheduleBlock),
  projected: List(AbsoluteInterval),
) -> Bool {
  list.all(blocks, fn(block) {
    let start = seconds(block.start)
    let end = seconds(block.end)
    list.any(projected, fn(interval) {
      start >= interval.start && end <= interval.end
    })
  })
}

fn task_constraints(
  tasks: List(task_model.Todo),
  blocks: List(ScheduleBlock),
) -> Bool {
  list.all(tasks, fn(task) {
    let own = list.filter(blocks, fn(block) { block.task_id == task.id })
    let total =
      list.fold(own, 0, fn(sum, block) {
        sum + { seconds(block.end) - seconds(block.start) } / 60
      })
    let minimum = task_model.effective_minimum_split(task)
    let due_seconds = case task.due {
      option.Some(value) -> due.to_unix_seconds(value)
      option.None -> 0
    }
    total <= task.estimate_minutes
    && list.all(own, fn(block) {
      { seconds(block.end) - seconds(block.start) } / 60 >= minimum
      && seconds(block.end) <= due_seconds
    })
  })
}

fn has_task(tasks: List(task_model.Todo), id: Int) -> Bool {
  list.any(tasks, fn(task) { task.id == id })
}

fn no_overlap(
  blocks: List(ScheduleBlock),
  previous_end: option.Option(Int),
) -> Bool {
  case blocks {
    [] -> True
    [block, ..rest] -> {
      let start = seconds(block.start)
      let end = seconds(block.end)
      case previous_end {
        option.None -> no_overlap(rest, option.Some(end))
        option.Some(previous) ->
          start >= previous && no_overlap(rest, option.Some(end))
      }
    }
  }
}

fn merge_adjacent(
  values: List(ScheduleBlock),
  acc: List(ScheduleBlock),
) -> List(ScheduleBlock) {
  case values, acc {
    [], _ -> acc
    [next, ..rest], [] -> merge_adjacent(rest, [next])
    [next, ..rest], [current, ..previous] ->
      case
        current.task_id == next.task_id
        && seconds(current.end) == seconds(next.start)
      {
        True ->
          merge_adjacent(rest, [
            ScheduleBlock(current.task_id, current.start, next.end),
            ..previous
          ])
        False -> merge_adjacent(rest, [next, current, ..previous])
      }
  }
}

pub fn block_compare(a: ScheduleBlock, b: ScheduleBlock) -> order.Order {
  case int.compare(seconds(a.start), seconds(b.start)) {
    order.Eq ->
      case int.compare(a.task_id, b.task_id) {
        order.Eq -> int.compare(seconds(a.end), seconds(b.end))
        other -> other
      }
    other -> other
  }
}

pub fn block_key_compare(a: ScheduleBlock, b: ScheduleBlock) -> order.Order {
  case int.compare(a.task_id, b.task_id) {
    order.Eq ->
      case int.compare(seconds(a.start), seconds(b.start)) {
        order.Eq -> int.compare(seconds(a.end), seconds(b.end))
        other -> other
      }
    other -> other
  }
}

pub fn seconds(value) -> Int {
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(value)
  seconds
}

fn nanoseconds(value) -> Int {
  let #(_, nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(value)
  nanoseconds
}

pub fn floor_mod(value: Int, modulus: Int) -> Int {
  let raw = value % modulus
  case raw < 0 {
    True -> raw + modulus
    False -> raw
  }
}
