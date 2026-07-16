import gleam/int
import gleam/list
import gleam/option
import tasks/domain/model as task_model
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score
import tasks/domain/scheduling/timeline.{type AbsoluteInterval}

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

type Candidate {
  Candidate(
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
      let current_contributions =
        score.contributions(tasks, blocks, planning_start)
      let current_score = score.total(current_contributions)
      let candidate =
        rebuilds(tasks)
        |> list.fold(option.None, fn(best, rebuild) {
          let Rebuild(selected) = rebuild
          let greedy.RebuildResult(next, replacements) =
            greedy.rebuild(blocks, selected, projected, planning_start, offset)
          case next == blocks {
            True -> best
            False -> {
              // A rebuild changes only its selected tasks; reuse every other score.
              let next_score =
                score.replace_contributions(current_contributions, replacements)
                |> score.total
              case score.strictly_better(next_score, than: current_score) {
                False -> best
                True -> choose_better(best, Candidate(next, next_score))
              }
            }
          }
        })
      case candidate {
        option.None -> HillResult(blocks, accepted, list.reverse(scores))
        option.Some(Candidate(next, next_score)) ->
          // Greedy construction should already be valid; validate accepted states
          // so a placement bug cannot propagate through the search.
          case
            invariant.validate_generation(
              next,
              tasks,
              projected,
              planning_start,
              offset,
            )
          {
            Error(_) -> HillResult(blocks, accepted, list.reverse(scores))
            Ok(valid) ->
              climb_loop(
                valid,
                tasks,
                projected,
                planning_start,
                offset,
                accepted + 1,
                [next_score, ..scores],
              )
          }
      }
    }
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
        // Stable enumeration is the deterministic tie-break.
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
