import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import tasks/domain/policy
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{
  type AbsoluteInterval, type SearchSpace, AbsoluteInterval, SearchSpace,
}

const placement_candidate_limit = 20_000

type Candidate {
  Candidate(
    block: scheduling_model.ScheduleBlock,
    own_blocks: List(scheduling_model.ScheduleBlock),
    score: scheduling_model.Score,
  )
}

pub fn build(
  tasks: List(scheduling_model.SchedulingTask),
  space: SearchSpace,
) -> List(scheduling_model.ScheduleBlock) {
  tasks
  |> initial_order
  |> list.fold([], fn(blocks, task) { place_task(blocks, task, space) })
}

pub fn rebuild(
  blocks: List(scheduling_model.ScheduleBlock),
  selected: List(scheduling_model.SchedulingTask),
  space: SearchSpace,
) -> List(scheduling_model.ScheduleBlock) {
  let selected_ids = list.map(selected, fn(task) { task.id })
  // Filtering positive, non-overlapping blocks preserves canonical order.
  let base =
    blocks
    |> list.filter(fn(block) { !list.contains(selected_ids, block.task_id) })
  list.fold(selected, base, fn(current, task) {
    place_task(current, task, space)
  })
}

fn initial_order(
  tasks: List(scheduling_model.SchedulingTask),
) -> List(scheduling_model.SchedulingTask) {
  list.sort(tasks, by: task_compare)
}

fn place_task(
  blocks: List(scheduling_model.ScheduleBlock),
  task: scheduling_model.SchedulingTask,
  space: SearchSpace,
) -> List(scheduling_model.ScheduleBlock) {
  let own_blocks =
    list.filter(blocks, fn(existing) { existing.task_id == task.id })
  place_remaining(blocks, own_blocks, task, space)
}

fn place_remaining(
  blocks: List(scheduling_model.ScheduleBlock),
  own_blocks: List(scheduling_model.ScheduleBlock),
  task: scheduling_model.SchedulingTask,
  space: SearchSpace,
) -> List(scheduling_model.ScheduleBlock) {
  case best_placement(blocks, own_blocks, task, space) {
    option.None -> blocks
    option.Some(candidate) ->
      place_remaining(
        invariant.insert_canonical(blocks, candidate.block),
        candidate.own_blocks,
        task,
        space,
      )
  }
}

fn best_placement(
  blocks: List(scheduling_model.ScheduleBlock),
  own_blocks: List(scheduling_model.ScheduleBlock),
  task: scheduling_model.SchedulingTask,
  space: SearchSpace,
) -> option.Option(Candidate) {
  let SearchSpace(projected, planning_start, offset) = space
  let placed = score.placed_minutes(own_blocks)
  let remaining = task.estimate_minutes - placed
  case remaining <= 0 {
    True -> option.None
    False -> {
      let intervals =
        timeline.free_intervals(projected, blocks)
        |> list.map(fn(interval) {
          AbsoluteInterval(
            interval.start,
            int.min(interval.end, task.deadline_seconds),
          )
        })
      let maximum_capacity =
        list.fold(intervals, 0, fn(maximum, interval) {
          int.max(maximum, { interval.end - interval.start } / 60)
        })
      let block_length = int.min(remaining, maximum_capacity)
      case block_length < scheduling_model.effective_minimum_split(task) {
        True -> option.None
        False ->
          // Choose the global maximum before applying the candidate budget so
          // fragmentation cannot hide a longer, primary-score-winning block.
          intervals
          |> list.flat_map(fn(interval) {
            let capacity = { interval.end - interval.start } / 60
            case capacity < block_length {
              True -> []
              False ->
                anchors(
                  task,
                  placed,
                  interval,
                  block_length,
                  planning_start,
                  offset,
                )
            }
          })
          |> list.take(placement_candidate_limit)
          |> list.fold(option.None, fn(best, start) {
            let block =
              scheduling_model.ScheduleBlock(
                task.id,
                start,
                start + block_length * 60,
              )
            let next_own = invariant.insert_canonical(own_blocks, block)
            // Other tasks are unchanged, so their scores cancel.
            choose_better(
              best,
              Candidate(
                block,
                next_own,
                score.evaluate_task(task, next_own, planning_start),
              ),
            )
          })
      }
    }
  }
}

fn anchors(
  task: scheduling_model.SchedulingTask,
  placed: Int,
  interval: AbsoluteInterval,
  block_length: Int,
  planning_start: Int,
  offset: Int,
) -> List(Int) {
  let estimate = int.to_float(task.estimate_minutes)
  let y0 = int.to_float(placed) /. estimate
  let y1 = int.to_float(placed + block_length) /. estimate
  let span = int.to_float(task.deadline_seconds - planning_start)
  let ideal_start =
    int.to_float(planning_start)
    +. policy.inverse(task.scheduling_policy, y0)
    *. span
  let ideal_end =
    int.to_float(planning_start)
    +. policy.inverse(task.scheduling_policy, y1)
    *. span
  [
    interval.start,
    interval.end - block_length * 60,
    rounded_local(ideal_start, offset),
    rounded_local(ideal_end, offset) - block_length * 60,
  ]
  |> list.map(fn(start) {
    int.max(interval.start, int.min(start, interval.end - block_length * 60))
  })
  |> list.unique
}

fn choose_better(
  current: option.Option(Candidate),
  candidate: Candidate,
) -> option.Option(Candidate) {
  case current {
    option.None -> option.Some(candidate)
    option.Some(existing) ->
      case score.compare(candidate.score, existing.score) {
        order.Lt -> option.Some(candidate)
        order.Gt -> current
        order.Eq ->
          case invariant.block_key_compare(candidate.block, existing.block) {
            order.Lt -> option.Some(candidate)
            _ -> current
          }
      }
  }
}

fn task_compare(
  a: scheduling_model.SchedulingTask,
  b: scheduling_model.SchedulingTask,
) -> order.Order {
  case int.compare(b.priority, a.priority) {
    order.Eq ->
      case int.compare(a.deadline_seconds, b.deadline_seconds) {
        order.Eq -> int.compare(a.id, b.id)
        other -> other
      }
    other -> other
  }
}

fn rounded_local(value, offset) {
  float.round({ value +. int.to_float(offset) } /. 60.0) * 60 - offset
}
