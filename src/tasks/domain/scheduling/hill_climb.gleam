import gleam/list
import gleam/option
import gleam/order
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/neighborhood
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{type SearchSpace, SearchSpace}
import tasks/runtime/parallel

pub const accepted_move_limit = 1000

pub const rebuild_candidate_limit = 20_000

pub type HillResult {
  HillResult(
    blocks: List(scheduling_model.ScheduleBlock),
    accepted_moves: Int,
    accepted_scores: List(scheduling_model.Score),
  )
}

type IndexedRebuild {
  IndexedRebuild(index: Int, rebuild: neighborhood.Rebuild)
}

type Candidate {
  Candidate(
    index: Int,
    blocks: List(scheduling_model.ScheduleBlock),
    contributions: List(score.Contribution),
    score: scheduling_model.Score,
  )
}

type SearchState {
  SearchState(
    blocks: List(scheduling_model.ScheduleBlock),
    contributions: List(score.Contribution),
    accepted_moves: Int,
    accepted_scores_reversed: List(scheduling_model.Score),
  )
}

pub fn improve(initial, tasks, space) {
  climb(initial, tasks, space).blocks
}

pub fn climb(
  initial: List(scheduling_model.ScheduleBlock),
  tasks: List(scheduling_model.SchedulingTask),
  space: SearchSpace,
) -> HillResult {
  let SearchSpace(_, planning_start, _) = space
  let contributions = score.contributions(tasks, initial, planning_start)
  climb_loop(
    SearchState(initial, contributions, 0, []),
    tasks,
    neighborhood.generate(tasks, rebuild_candidate_limit)
      |> list.index_map(fn(rebuild, index) { IndexedRebuild(index, rebuild) }),
    space,
  )
}

fn climb_loop(state, tasks, rebuild_candidates, space) {
  let SearchState(blocks, contributions, accepted, scores) = state
  let current_score = score.total(contributions)
  case accepted >= accepted_move_limit {
    True -> HillResult(blocks, accepted, list.reverse(scores))
    False -> {
      let candidate =
        evaluate_candidates(
          rebuild_candidates,
          blocks,
          contributions,
          current_score,
          space,
        )
      case candidate {
        option.None -> HillResult(blocks, accepted, list.reverse(scores))
        option.Some(Candidate(_, next, next_contributions, next_score)) ->
          // Greedy construction should already be valid; validate accepted states
          // so a placement bug cannot propagate through the search.
          case invariant.validate_generation(next, tasks, space) {
            Error(_) -> HillResult(blocks, accepted, list.reverse(scores))
            Ok(valid) ->
              climb_loop(
                SearchState(valid, next_contributions, accepted + 1, [
                  next_score,
                  ..scores
                ]),
                tasks,
                rebuild_candidates,
                space,
              )
          }
      }
    }
  }
}

fn evaluate_candidates(
  rebuild_candidates,
  blocks,
  current_contributions,
  current_score,
  space,
) {
  parallel.map_chunks_reduce(
    rebuild_candidates,
    option.None,
    fn(chunk) {
      evaluate_chunk(chunk, blocks, current_contributions, current_score, space)
    },
    merge_candidate,
  )
}

fn evaluate_chunk(
  rebuild_candidates,
  blocks,
  current_contributions,
  current_score,
  space,
) {
  let SearchSpace(_, planning_start, _) = space
  rebuild_candidates
  |> list.fold(option.None, fn(best, indexed) {
    let IndexedRebuild(index, rebuild) = indexed
    let selected = neighborhood.tasks(rebuild)
    let next = greedy.rebuild(blocks, selected, space)
    case next == blocks {
      True -> best
      False -> {
        // A rebuild changes only its selected tasks; reuse every other score.
        let replacements = score.contributions(selected, next, planning_start)
        let next_contributions =
          score.replace_contributions(current_contributions, replacements)
        let next_score = score.total(next_contributions)
        case score.strictly_better(next_score, than: current_score) {
          False -> best
          True ->
            choose_better(
              best,
              Candidate(index, next, next_contributions, next_score),
            )
        }
      }
    }
  })
}

fn merge_candidate(best, candidate) {
  case candidate {
    option.None -> best
    option.Some(candidate) -> choose_better(best, candidate)
  }
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
        order.Eq if candidate.index < existing.index -> option.Some(candidate)
        order.Eq | order.Gt -> current
      }
  }
}
