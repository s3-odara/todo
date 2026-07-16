import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/time/timestamp
import tasks/domain/due
import tasks/domain/model as task_model
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model.{type ScheduleBlock, ScheduleBlock}
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{type AbsoluteInterval, AbsoluteInterval}

pub type MoveKind {
  Add
  Relocate
  Swap
  Split
  Merge
}

pub type Repack {
  Repack(
    kind: MoveKind,
    remove: List(ScheduleBlock),
    insert: List(ScheduleBlock),
  )
}

type CandidateBuffer {
  CandidateBuffer(values: List(Repack), count: Int, limit: Int)
}

pub const candidate_limit = 20_000

pub fn kind_rank(kind: MoveKind) -> Int {
  case kind {
    Add -> 0
    Relocate -> 1
    Swap -> 2
    Split -> 3
    Merge -> 4
  }
}

pub fn apply_repack(
  blocks: List(ScheduleBlock),
  repack: Repack,
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> Result(List(ScheduleBlock), invariant.InvariantError) {
  use removed <- result.try(remove_requested(blocks, repack.remove))
  list.append(removed, repack.insert)
  |> invariant.canonicalize
  |> invariant.validate_generation(tasks, projected, planning_start, offset)
}

pub fn add_candidates(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> List(Repack) {
  add_candidates_up_to(
    blocks,
    tasks,
    projected,
    planning_start,
    offset,
    candidate_limit,
  )
}

fn add_candidates_up_to(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
  limit: Int,
) -> List(Repack) {
  let free = timeline_free(projected, blocks)
  list.fold(tasks, new_buffer(limit), fn(acc, task) {
    fold_placements(
      task,
      blocks,
      free,
      planning_start,
      offset,
      [],
      acc,
      fn(acc, block) { bounded_insert(acc, Repack(Add, [], [block])) },
    )
  })
  |> buffer_values
}

pub fn relocate_candidates(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> List(Repack) {
  relocate_candidates_up_to(
    blocks,
    tasks,
    projected,
    planning_start,
    offset,
    candidate_limit,
  )
}

fn relocate_candidates_up_to(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
  limit: Int,
) -> List(Repack) {
  list.fold(blocks, new_buffer(limit), fn(acc, block) {
    let base = delete_once(blocks, block)
    case find_task(tasks, block.task_id) {
      Error(_) -> acc
      Ok(task) ->
        fold_placements(
          task,
          base,
          timeline_free(projected, base),
          planning_start,
          offset,
          [length(block)],
          acc,
          fn(acc, candidate) {
            case length(candidate) == length(block) && candidate != block {
              True ->
                bounded_insert(acc, Repack(Relocate, [block], [candidate]))
              False -> acc
            }
          },
        )
    }
  })
  |> buffer_values
}

pub fn swap_candidates(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
) -> List(Repack) {
  swap_candidates_up_to(blocks, tasks, candidate_limit)
}

fn swap_candidates_up_to(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  limit: Int,
) -> List(Repack) {
  fold_pairs(blocks, new_buffer(limit), fn(acc, a, b) {
    case a.task_id == b.task_id {
      True -> acc
      False -> {
        let inserted = [
          ScheduleBlock(b.task_id, a.start, a.end),
          ScheduleBlock(a.task_id, b.start, b.end),
        ]
        case valid_insert_lengths(inserted, tasks) {
          True -> bounded_insert(acc, Repack(Swap, [a, b], inserted))
          False -> acc
        }
      }
    }
  })
  |> buffer_values
}

pub fn split_candidates(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> List(Repack) {
  split_candidates_up_to(
    blocks,
    tasks,
    projected,
    planning_start,
    offset,
    candidate_limit,
  )
}

fn split_candidates_up_to(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
  limit: Int,
) -> List(Repack) {
  list.fold(blocks, new_buffer(limit), fn(acc, block) {
    case find_task(tasks, block.task_id) {
      Error(_) -> acc
      Ok(task) -> {
        let minimum = effective_minimum(task)
        let total = length(block)
        case total >= minimum * 2 {
          False -> acc
          True -> {
            let left_length = total / 2
            let right_length = total - left_length
            let base = delete_once(blocks, block)
            fold_placements(
              task,
              base,
              timeline_free(projected, base),
              planning_start,
              offset,
              [left_length],
              acc,
              fn(acc, first) {
                case length(first) == left_length {
                  False -> acc
                  True -> {
                    let with_first = invariant.canonicalize([first, ..base])
                    fold_placements(
                      task,
                      with_first,
                      timeline_free(projected, with_first),
                      planning_start,
                      offset,
                      [right_length],
                      acc,
                      fn(acc, second) {
                        case length(second) == right_length {
                          True ->
                            bounded_insert(
                              acc,
                              Repack(Split, [block], [first, second]),
                            )
                          False -> acc
                        }
                      },
                    )
                  }
                }
              },
            )
          }
        }
      }
    }
  })
  |> buffer_values
}

pub fn merge_candidates(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> List(Repack) {
  merge_candidates_up_to(
    blocks,
    tasks,
    projected,
    planning_start,
    offset,
    candidate_limit,
  )
}

fn merge_candidates_up_to(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
  limit: Int,
) -> List(Repack) {
  fold_pairs(blocks, new_buffer(limit), fn(acc, a, b) {
    case a.task_id == b.task_id {
      False -> acc
      True -> {
        let base = delete_once(delete_once(blocks, a), b)
        case find_task(tasks, a.task_id) {
          Error(_) -> acc
          Ok(task) ->
            fold_placements(
              task,
              base,
              timeline_free(projected, base),
              planning_start,
              offset,
              [length(a) + length(b)],
              acc,
              fn(acc, candidate) {
                case length(candidate) == length(a) + length(b) {
                  True ->
                    bounded_insert(acc, Repack(Merge, [a, b], [candidate]))
                  False -> acc
                }
              },
            )
        }
      }
    }
  })
  |> buffer_values
}

pub fn all_candidates(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> List(Repack) {
  let add =
    add_candidates_up_to(
      blocks,
      tasks,
      projected,
      planning_start,
      offset,
      candidate_limit,
    )
  let relocate = case candidate_limit - list.length(add) {
    0 -> []
    remaining ->
      relocate_candidates_up_to(
        blocks,
        tasks,
        projected,
        planning_start,
        offset,
        remaining,
      )
  }
  let swap = case candidate_limit - list.length(add) - list.length(relocate) {
    0 -> []
    remaining -> swap_candidates_up_to(blocks, tasks, remaining)
  }
  let split = case
    candidate_limit
    - list.length(add)
    - list.length(relocate)
    - list.length(swap)
  {
    0 -> []
    remaining ->
      split_candidates_up_to(
        blocks,
        tasks,
        projected,
        planning_start,
        offset,
        remaining,
      )
  }
  let merge = case
    candidate_limit
    - list.length(add)
    - list.length(relocate)
    - list.length(swap)
    - list.length(split)
  {
    0 -> []
    remaining ->
      merge_candidates_up_to(
        blocks,
        tasks,
        projected,
        planning_start,
        offset,
        remaining,
      )
  }
  [add, relocate, swap, split, merge] |> list.flatten
}

fn fold_placements(
  task: task_model.Todo,
  blocks: List(ScheduleBlock),
  free: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
  forced_lengths: List(Int),
  initial: accumulator,
  collect: fn(accumulator, ScheduleBlock) -> accumulator,
) -> accumulator {
  let remaining = task.estimate_minutes - score.placed_minutes(task.id, blocks)
  case remaining <= 0 {
    True -> initial
    False ->
      list.fold(free, initial, fn(acc, interval) {
        let due_seconds = case task.due {
          option.Some(value) -> due.to_unix_seconds(value)
          option.None -> interval.start
        }
        let clipped =
          AbsoluteInterval(interval.start, int.min(interval.end, due_seconds))
        let capacity = { clipped.end - clipped.start } / 60
        case capacity <= 0 {
          True -> acc
          False -> {
            let minimum = effective_minimum(task)
            let cap = int.min(remaining, capacity)
            let existing_lengths = list.map(blocks, length)
            let raw_lengths = case forced_lengths {
              [] -> [minimum, cap, remaining - minimum, ..existing_lengths]
              _ -> forced_lengths
            }
            raw_lengths
            |> unique_ints
            |> list.filter(fn(value) { value >= minimum && value <= cap })
            |> list.fold(acc, fn(acc, value) {
              anchors(task, blocks, clipped, value, planning_start, offset)
              |> list.fold(acc, fn(acc, start) {
                collect(
                  acc,
                  ScheduleBlock(
                    task.id,
                    timestamp.from_unix_seconds(start),
                    timestamp.from_unix_seconds(start + value * 60),
                  ),
                )
              })
            })
          }
        }
      })
  }
}

fn anchors(
  task: task_model.Todo,
  blocks: List(ScheduleBlock),
  interval: AbsoluteInterval,
  block_length: Int,
  planning_start: Int,
  offset: Int,
) -> List(Int) {
  let placed = score.placed_minutes(task.id, blocks)
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

fn timeline_free(
  projected: List(AbsoluteInterval),
  blocks: List(ScheduleBlock),
) -> List(AbsoluteInterval) {
  timeline.free_intervals(projected, blocks)
}

fn effective_minimum(task: task_model.Todo) -> Int {
  case task.estimate_minutes < task.minimum_split_minutes {
    True -> task.estimate_minutes
    False -> task.minimum_split_minutes
  }
}

fn valid_insert_lengths(
  blocks: List(ScheduleBlock),
  tasks: List(task_model.Todo),
) -> Bool {
  list.all(blocks, fn(block) {
    case find_task(tasks, block.task_id) {
      Ok(task) -> length(block) >= effective_minimum(task)
      Error(_) -> False
    }
  })
}

pub fn length(block: ScheduleBlock) -> Int {
  { invariant.seconds(block.end) - invariant.seconds(block.start) } / 60
}

fn find_task(
  tasks: List(task_model.Todo),
  id: Int,
) -> Result(task_model.Todo, Nil) {
  list.find(tasks, fn(task) { task.id == id })
}

fn remove_requested(
  blocks: List(ScheduleBlock),
  requested: List(ScheduleBlock),
) -> Result(List(ScheduleBlock), invariant.InvariantError) {
  case requested {
    [] -> Ok(blocks)
    [block, ..rest] ->
      case list.contains(blocks, block) {
        False -> Error(invariant.InvalidSchedule)
        True -> remove_requested(delete_once(blocks, block), rest)
      }
  }
}

fn delete_once(values, target) {
  case values {
    [] -> []
    [first, ..rest] ->
      case first == target {
        True -> rest
        False -> [first, ..delete_once(rest, target)]
      }
  }
}

fn fold_pairs(
  values: List(ScheduleBlock),
  initial: accumulator,
  collect: fn(accumulator, ScheduleBlock, ScheduleBlock) -> accumulator,
) -> accumulator {
  case values {
    [] -> initial
    [first, ..rest] -> {
      let next =
        list.fold(rest, initial, fn(acc, second) { collect(acc, first, second) })
      fold_pairs(rest, next, collect)
    }
  }
}

fn unique_ints(values) {
  list.fold(values, [], fn(acc, value) {
    case list.contains(acc, value) {
      True -> acc
      False -> [value, ..acc]
    }
  })
  |> list.reverse
}

fn new_buffer(limit: Int) -> CandidateBuffer {
  CandidateBuffer([], 0, limit)
}

fn buffer_values(buffer: CandidateBuffer) -> List(Repack) {
  list.reverse(buffer.values)
}

fn bounded_insert(buffer: CandidateBuffer, value: Repack) -> CandidateBuffer {
  let CandidateBuffer(values, count, limit) = buffer
  case values, count >= limit {
    _, True ->
      case values {
        [greatest, ..] ->
          case repack_compare(value, greatest) {
            order.Gt -> buffer
            order.Eq -> buffer
            order.Lt -> {
              let #(next, inserted) = insert_unique_descending(values, value)
              case inserted {
                True -> CandidateBuffer(list.drop(next, 1), count, limit)
                False -> buffer
              }
            }
          }
        [] -> buffer
      }
    _, False -> {
      let #(next, inserted) = insert_unique_descending(values, value)
      CandidateBuffer(
        next,
        case inserted {
          True -> count + 1
          False -> count
        },
        limit,
      )
    }
  }
}

fn insert_unique_descending(values: List(Repack), value: Repack) {
  case values {
    [] -> #([value], True)
    [first, ..rest] ->
      case repack_compare(value, first) {
        order.Gt -> #([value, first, ..rest], True)
        order.Eq -> #(values, False)
        order.Lt -> {
          let #(next, inserted) = insert_unique_descending(rest, value)
          #([first, ..next], inserted)
        }
      }
  }
}

pub fn repack_compare(a: Repack, b: Repack) -> order.Order {
  case int.compare(kind_rank(a.kind), kind_rank(b.kind)) {
    order.Eq ->
      case
        block_lists_compare(
          list.sort(a.remove, by: invariant.block_key_compare),
          list.sort(b.remove, by: invariant.block_key_compare),
        )
      {
        order.Eq ->
          block_lists_compare(
            list.sort(a.insert, by: invariant.block_key_compare),
            list.sort(b.insert, by: invariant.block_key_compare),
          )
        other -> other
      }
    other -> other
  }
}

fn block_lists_compare(a, b) {
  case a, b {
    [], [] -> order.Eq
    [], _ -> order.Lt
    _, [] -> order.Gt
    [x, ..xs], [y, ..ys] ->
      case invariant.block_key_compare(x, y) {
        order.Eq -> block_lists_compare(xs, ys)
        other -> other
      }
  }
}
