import gleam/int
import gleam/list
import gleam/option
import tasks/domain/model as task_model
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score
import tasks/domain/scheduling/search.{type SearchSpace, SearchSpace}
import tasks/runtime/parallel

pub const accepted_move_limit = 1000

pub const candidate_limit = 20_000

pub type HillResult {
  HillResult(
    blocks: List(scheduling_model.ScheduleBlock),
    accepted_moves: Int,
    accepted_scores: List(scheduling_model.Score),
  )
}

// Rebuilding one task, an ordered pair, or an ordered triple subsumes
// block-level add, move, split, merge, and swap operations without separate
// mutation paths.
type Rebuild {
  Rebuild(tasks: List(task_model.Todo))
}

type IndexedRebuild {
  IndexedRebuild(index: Int, rebuild: Rebuild)
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
    total_score: scheduling_model.Score,
    accepted_moves: Int,
    accepted_scores_reversed: List(scheduling_model.Score),
  )
}

pub fn improve(initial, tasks, space) {
  climb(initial, tasks, space).blocks
}

pub fn climb(
  initial: List(scheduling_model.ScheduleBlock),
  tasks: List(task_model.Todo),
  space: SearchSpace,
) -> HillResult {
  let SearchSpace(_, planning_start, _) = space
  let contributions = score.contributions(tasks, initial, planning_start)
  climb_loop(
    SearchState(initial, contributions, score.total(contributions), 0, []),
    tasks,
    rebuilds(tasks)
      |> list.index_map(fn(rebuild, index) { IndexedRebuild(index, rebuild) }),
    space,
  )
}

fn climb_loop(state, tasks, rebuild_candidates, space) {
  let SearchState(blocks, contributions, current_score, accepted, scores) =
    state
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
                SearchState(
                  valid,
                  next_contributions,
                  next_score,
                  accepted + 1,
                  [next_score, ..scores],
                ),
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
  rebuild_candidates
  |> list.fold(option.None, fn(best, indexed) {
    let IndexedRebuild(index, Rebuild(selected)) = indexed
    let greedy.RebuildResult(next, replacements) =
      greedy.rebuild(blocks, selected, space)
    case next == blocks {
      True -> best
      False -> {
        // A rebuild changes only its selected tasks; reuse every other score.
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
        score.Better -> option.Some(candidate)
        score.Equal if candidate.index < existing.index ->
          option.Some(candidate)
        score.Equal | score.Worse -> current
      }
  }
}

fn rebuilds(tasks: List(task_model.Todo)) -> List(Rebuild) {
  let ordered = list.sort(tasks, by: task_id_compare)
  let singles =
    ordered
    |> list.take(candidate_limit)
    |> list.map(fn(task) { Rebuild([task]) })
  let remaining = candidate_limit - list.length(singles)
  case remaining <= 0 {
    True -> singles
    False -> {
      let pairs = pair_rebuilds(ordered, remaining, [])
      let triple_budget = remaining - list.length(pairs)
      case triple_budget <= 0 {
        True -> list.append(singles, pairs)
        False ->
          list.append(
            singles,
            list.append(pairs, triple_rebuilds(ordered, triple_budget, [])),
          )
      }
    }
  }
}

fn pair_rebuilds(
  tasks: List(task_model.Todo),
  remaining: Int,
  acc: List(Rebuild),
) -> List(Rebuild) {
  case tasks, remaining <= 0 {
    _, True -> list.reverse(acc)
    [], _ | [_], _ -> list.reverse(acc)
    [first, ..rest], False -> pairs_with(first, rest, rest, remaining, acc)
  }
}

fn pairs_with(
  first: task_model.Todo,
  candidates: List(task_model.Todo),
  next_outer: List(task_model.Todo),
  remaining: Int,
  acc: List(Rebuild),
) -> List(Rebuild) {
  case candidates, remaining {
    _, remaining if remaining <= 0 -> list.reverse(acc)
    [], _ -> pair_rebuilds(next_outer, remaining, acc)
    [second, ..], 1 -> list.reverse([Rebuild([first, second]), ..acc])
    [second, ..rest], _ ->
      pairs_with(first, rest, next_outer, remaining - 2, [
        Rebuild([second, first]),
        Rebuild([first, second]),
        ..acc
      ])
  }
}

fn triple_rebuilds(
  tasks: List(task_model.Todo),
  remaining: Int,
  acc: List(Rebuild),
) -> List(Rebuild) {
  case tasks, remaining <= 0 {
    _, True -> list.reverse(acc)
    [], _ | [_], _ | [_, _], _ -> list.reverse(acc)
    [first, ..rest], False ->
      triples_with_first(first, rest, rest, remaining, acc)
  }
}

fn triples_with_first(
  first: task_model.Todo,
  candidates: List(task_model.Todo),
  next_outer: List(task_model.Todo),
  remaining: Int,
  acc: List(Rebuild),
) -> List(Rebuild) {
  case candidates, remaining <= 0 {
    _, True -> list.reverse(acc)
    [], False | [_], False -> triple_rebuilds(next_outer, remaining, acc)
    [second, ..rest], False ->
      triples_with_pair(first, second, rest, rest, next_outer, remaining, acc)
  }
}

fn triples_with_pair(
  first: task_model.Todo,
  second: task_model.Todo,
  candidates: List(task_model.Todo),
  next_second: List(task_model.Todo),
  next_outer: List(task_model.Todo),
  remaining: Int,
  acc: List(Rebuild),
) -> List(Rebuild) {
  case candidates, remaining <= 0 {
    _, True -> list.reverse(acc)
    [], False ->
      triples_with_first(first, next_second, next_outer, remaining, acc)
    [third, ..rest], False -> {
      let permutations = [
        Rebuild([first, second, third]),
        Rebuild([first, third, second]),
        Rebuild([second, first, third]),
        Rebuild([second, third, first]),
        Rebuild([third, first, second]),
        Rebuild([third, second, first]),
      ]
      let selected = list.take(permutations, remaining)
      triples_with_pair(
        first,
        second,
        rest,
        next_second,
        next_outer,
        remaining - list.length(selected),
        list.append(list.reverse(selected), acc),
      )
    }
  }
}

fn task_id_compare(a: task_model.Todo, b: task_model.Todo) {
  int.compare(a.id, b.id)
}
