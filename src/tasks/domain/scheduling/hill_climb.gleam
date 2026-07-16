import gleam/list
import gleam/option
import gleam/order
import gleam/result
import tasks/domain/model as task_model
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/move
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{type AbsoluteInterval}

pub const accepted_move_limit = 1000

pub type HillResult {
  HillResult(
    blocks: List(scheduling_model.ScheduleBlock),
    accepted_moves: Int,
    accepted_scores: List(scheduling_model.Score),
  )
}

type Candidate {
  Candidate(
    repack: move.Repack,
    blocks: List(scheduling_model.ScheduleBlock),
    score: scheduling_model.Score,
  )
}

pub fn improve(initial, tasks, projected, planning_start, offset) {
  climb(initial, tasks, projected, planning_start, offset).blocks
}

pub fn climb(
  initial: List(scheduling_model.ScheduleBlock),
  tasks: List(task_model.Todo),
  projected: List(AbsoluteInterval),
  planning_start: Int,
  offset: Int,
) -> HillResult {
  climb_loop(initial, tasks, projected, planning_start, offset, 0, [])
}

fn climb_loop(
  blocks,
  tasks,
  projected,
  planning_start,
  offset,
  accepted,
  scores,
) {
  case accepted >= accepted_move_limit {
    True -> HillResult(blocks, accepted, list.reverse(scores))
    False -> {
      let current_score = score.evaluate(tasks, blocks, planning_start)
      let candidates =
        move.all_candidates(blocks, tasks, projected, planning_start, offset)
        |> list.filter_map(fn(repack) {
          move.apply_repack(
            blocks,
            repack,
            tasks,
            projected,
            planning_start,
            offset,
          )
          |> result.map(fn(next) {
            Candidate(repack, next, score.evaluate(tasks, next, planning_start))
          })
        })
        |> list.filter(fn(candidate) {
          score.strictly_better(candidate.score, than: current_score)
        })
      case best(candidates) {
        option.None -> HillResult(blocks, accepted, list.reverse(scores))
        option.Some(candidate) ->
          climb_loop(
            candidate.blocks,
            tasks,
            projected,
            planning_start,
            offset,
            accepted + 1,
            [candidate.score, ..scores],
          )
      }
    }
  }
}

fn best(candidates: List(Candidate)) -> option.Option(Candidate) {
  case candidates {
    [] -> option.None
    [first, ..rest] -> option.Some(best_loop(rest, first))
  }
}

fn best_loop(candidates: List(Candidate), existing: Candidate) -> Candidate {
  case candidates {
    [] -> existing
    [candidate, ..rest] -> {
      let chosen = case score.compare(candidate.score, existing.score) {
        score.Better -> candidate
        score.Worse -> existing
        score.Equal ->
          case move.repack_compare(candidate.repack, existing.repack) {
            order.Lt -> candidate
            _ -> existing
          }
      }
      best_loop(rest, chosen)
    }
  }
}
