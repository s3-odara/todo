import gleam/int
import gleam/list
import gleam/option
import gleam/order
import tasks/domain/local_time
import tasks/domain/model as task_model
import tasks/domain/scheduling/model.{
  type ScheduleBlock, type SchedulingTask, ScheduleBlock,
  effective_minimum_split,
}
import tasks/domain/scheduling/timeline.{
  type AbsoluteInterval, type SearchSpace, SearchSpace,
}

pub type InvariantError {
  InvalidSchedule
}

pub fn canonicalize(blocks: List(ScheduleBlock)) -> List(ScheduleBlock) {
  blocks
  |> list.sort(by: block_compare)
  |> merge_adjacent([])
  |> list.reverse
}

/// Insert a non-overlapping block into an already canonical schedule.
pub fn insert_canonical(
  blocks: List(ScheduleBlock),
  addition: ScheduleBlock,
) -> List(ScheduleBlock) {
  case blocks {
    [] -> [addition]
    [current, ..rest] ->
      case block_compare(addition, current) {
        order.Lt -> prepend_merging(addition, blocks)
        order.Eq | order.Gt ->
          prepend_merging(current, insert_canonical(rest, addition))
      }
  }
}

fn prepend_merging(
  block: ScheduleBlock,
  following: List(ScheduleBlock),
) -> List(ScheduleBlock) {
  case following {
    [next, ..rest]
      if block.task_id == next.task_id
      && block.end_seconds == next.start_seconds
    -> [
      ScheduleBlock(block.task_id, block.start_seconds, next.end_seconds),
      ..rest
    ]
    _ -> [block, ..following]
  }
}

/// Validate a newly generated state against all live scheduling constraints.
pub fn validate_generation(
  blocks: List(ScheduleBlock),
  tasks: List(SchedulingTask),
  space: SearchSpace,
) -> Result(Nil, InvariantError) {
  let SearchSpace(projected, planning_start, utc_offset_seconds) = space
  let canonical = canonicalize(blocks)
  case
    blocks == canonical
    && structural(canonical, utc_offset_seconds)
    && references_tasks(canonical, fn(id) {
      list.any(tasks, fn(task) { task.id == id })
    })
    && all_after(canonical, planning_start)
    && contained(canonical, projected)
    && task_constraints(tasks, canonical)
  {
    True -> Ok(Nil)
    False -> Error(InvalidSchedule)
  }
}

/// Persisted schedules are snapshots: only structural properties are live.
pub fn validate_persisted(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  utc_offset_seconds: Int,
) -> Result(Nil, InvariantError) {
  case
    blocks == canonicalize(blocks)
    && structural(blocks, utc_offset_seconds)
    && references_tasks(blocks, fn(id) {
      list.any(tasks, fn(task) { task.id == id })
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidSchedule)
  }
}

fn structural(blocks: List(ScheduleBlock), offset: Int) -> Bool {
  no_overlap(blocks, option.None)
  && list.all(blocks, fn(block) {
    let start = block.start_seconds
    let end = block.end_seconds
    start < end
    && local_time.floor_mod(start + offset, 60) == 0
    && local_time.floor_mod(end + offset, 60) == 0
  })
}

fn references_tasks(
  blocks: List(ScheduleBlock),
  has_task: fn(Int) -> Bool,
) -> Bool {
  list.all(blocks, fn(block) { has_task(block.task_id) })
}

fn all_after(blocks: List(ScheduleBlock), planning_start: Int) -> Bool {
  list.all(blocks, fn(block) { block.start_seconds >= planning_start })
}

fn contained(
  blocks: List(ScheduleBlock),
  projected: List(AbsoluteInterval),
) -> Bool {
  list.all(blocks, fn(block) {
    let start = block.start_seconds
    let end = block.end_seconds
    list.any(projected, fn(interval) {
      start >= interval.start && end <= interval.end
    })
  })
}

fn task_constraints(
  tasks: List(SchedulingTask),
  blocks: List(ScheduleBlock),
) -> Bool {
  list.all(tasks, fn(task) {
    let own = list.filter(blocks, fn(block) { block.task_id == task.id })
    let total =
      list.fold(own, 0, fn(sum, block) {
        sum + { block.end_seconds - block.start_seconds } / 60
      })
    let minimum = effective_minimum_split(task)
    total <= task.estimate_minutes
    && list.all(own, fn(block) {
      { block.end_seconds - block.start_seconds } / 60 >= minimum
      && block.end_seconds <= task.deadline_seconds
    })
  })
}

fn no_overlap(
  blocks: List(ScheduleBlock),
  previous_end: option.Option(Int),
) -> Bool {
  case blocks {
    [] -> True
    [block, ..rest] -> {
      let start = block.start_seconds
      let end = block.end_seconds
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
        && current.end_seconds == next.start_seconds
      {
        True ->
          merge_adjacent(rest, [
            ScheduleBlock(
              current.task_id,
              current.start_seconds,
              next.end_seconds,
            ),
            ..previous
          ])
        False -> merge_adjacent(rest, [next, current, ..previous])
      }
  }
}

pub fn block_compare(a: ScheduleBlock, b: ScheduleBlock) -> order.Order {
  case int.compare(a.start_seconds, b.start_seconds) {
    order.Eq ->
      case int.compare(a.task_id, b.task_id) {
        order.Eq -> int.compare(a.end_seconds, b.end_seconds)
        other -> other
      }
    other -> other
  }
}

pub fn block_key_compare(a: ScheduleBlock, b: ScheduleBlock) -> order.Order {
  case int.compare(a.task_id, b.task_id) {
    order.Eq ->
      case int.compare(a.start_seconds, b.start_seconds) {
        order.Eq -> int.compare(a.end_seconds, b.end_seconds)
        other -> other
      }
    other -> other
  }
}
