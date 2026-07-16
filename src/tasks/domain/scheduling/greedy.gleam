import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import tasks/domain/due
import tasks/domain/model as task_model
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/move
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{type AbsoluteInterval}

pub type Candidate {
  Candidate(
    repack: move.Repack,
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
  build_from([], tasks, projected, planning_start, offset)
}

fn build_from(blocks, tasks, projected, planning_start, offset) {
  let candidates =
    move.add_candidates(blocks, tasks, projected, planning_start, offset)
    |> list.filter_map(fn(repack) {
      move.apply_repack(
        blocks,
        repack,
        tasks,
        projected,
        planning_start,
        offset,
      )
      |> result.map(fn(result) {
        Candidate(repack, result, score.evaluate(tasks, result, planning_start))
      })
    })
  case best(candidates, tasks) {
    option.None -> blocks
    option.Some(candidate) ->
      build_from(candidate.blocks, tasks, projected, planning_start, offset)
  }
}

fn best(candidates: List(Candidate), tasks: List(task_model.Todo)) {
  list.fold(candidates, option.None, fn(current, candidate) {
    case current {
      option.None -> option.Some(candidate)
      option.Some(existing) ->
        case candidate_compare(candidate, existing, tasks) {
          order.Lt -> option.Some(candidate)
          _ -> current
        }
    }
  })
}

fn candidate_compare(a: Candidate, b: Candidate, tasks) {
  case score.compare(a.score, b.score) {
    score.Better -> order.Lt
    score.Worse -> order.Gt
    score.Equal -> tie_compare(a.repack, b.repack, tasks)
  }
}

fn tie_compare(a: move.Repack, b: move.Repack, tasks) {
  case list.first(a.insert), list.first(b.insert) {
    Ok(ab), Ok(bb) ->
      case task_for(tasks, ab.task_id), task_for(tasks, bb.task_id) {
        Ok(at), Ok(bt) -> compare_task_and_block(at, ab, bt, bb, a, b)
        _, _ -> move.repack_compare(a, b)
      }
    _, _ -> move.repack_compare(a, b)
  }
}

fn compare_task_and_block(
  at: task_model.Todo,
  ab: scheduling_model.ScheduleBlock,
  bt: task_model.Todo,
  bb: scheduling_model.ScheduleBlock,
  a: move.Repack,
  b: move.Repack,
) -> order.Order {
  case int.compare(bt.priority, at.priority) {
    order.Eq ->
      case int.compare(due_seconds(at), due_seconds(bt)) {
        order.Eq ->
          case int.compare(at.id, bt.id) {
            order.Eq ->
              case
                int.compare(
                  invariant.seconds(ab.start),
                  invariant.seconds(bb.start),
                )
              {
                order.Eq ->
                  case
                    int.compare(
                      invariant.seconds(ab.end),
                      invariant.seconds(bb.end),
                    )
                  {
                    order.Eq -> move.repack_compare(a, b)
                    other -> other
                  }
                other -> other
              }
            other -> other
          }
        other -> other
      }
    other -> other
  }
}

fn task_for(tasks: List(task_model.Todo), id: Int) {
  list.find(tasks, fn(task) { task.id == id })
}

fn due_seconds(task: task_model.Todo) {
  case task.due {
    option.Some(value) -> due.to_unix_seconds(value)
    option.None -> 0
  }
}
