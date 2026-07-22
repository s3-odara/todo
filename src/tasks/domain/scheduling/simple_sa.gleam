import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import tasks/domain/scheduling/deterministic_rng.{type Rng}
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score.{type Contribution}
import tasks/domain/scheduling/timeline.{type SearchSpace, SearchSpace}

/// Maximum deterministic search-chain budget.
pub const search_iterations = 16_384

/// Initial budget used when greedy places every requested minute.
pub const probe_iterations = 1024

const temperature_start = 1.0

const temperature_end = 0.01

type Solution {
  Solution(
    blocks: List(scheduling_model.ScheduleBlock),
    score: scheduling_model.Score,
    contributions: List(Contribution),
  )
}

type State {
  State(current: Solution, best: Solution, rng: Rng)
}

type Proposal {
  Proposal(selected: List(scheduling_model.SchedulingTask), rng: Rng)
}

pub type SearchResult {
  SearchResult(
    blocks: List(scheduling_model.ScheduleBlock),
    executed_iterations: Int,
  )
}

/// Adaptively improve the unchanged greedy solution with Simple SA.
/// The explicit seed makes the pure search reproducible. Different workloads
/// intentionally share its random stream; their candidate sets drive divergence.
pub fn improve(
  tasks: List(scheduling_model.SchedulingTask),
  space: SearchSpace,
  run_seed: Int,
) -> SearchResult {
  let SearchSpace(_, planning_start, _) = space
  let greedy_blocks = greedy.build(tasks, space)
  let greedy_contributions =
    score.contributions(tasks, greedy_blocks, planning_start)
  let greedy_score = score.total(greedy_contributions)
  let greedy_solution =
    Solution(greedy_blocks, greedy_score, greedy_contributions)
  let estimate = weighted_estimate(tasks)
  case tasks == [] || estimate <= 0 {
    True -> SearchResult(greedy_blocks, 0)
    False -> {
      let initial =
        State(greedy_solution, greedy_solution, deterministic_rng.new(run_seed))
      let #(final, executed_iterations) = case
        has_actual_unscheduled(tasks, greedy_blocks)
      {
        True -> #(
          loop(tasks, space, estimate, 0, search_iterations, initial),
          search_iterations,
        )
        False -> {
          let probed =
            loop(tasks, space, estimate, 0, probe_iterations, initial)
          // A policy-only gain must exceed epsilon to earn the full budget.
          case score.strictly_better(probed.best.score, greedy_score) {
            True -> #(
              loop(
                tasks,
                space,
                estimate,
                probe_iterations,
                search_iterations,
                probed,
              ),
              search_iterations,
            )
            False -> #(initial, probe_iterations)
          }
        }
      }
      let blocks = case score.compare(final.best.score, greedy_score) {
        order.Lt -> final.best.blocks
        order.Eq | order.Gt -> greedy_blocks
      }
      SearchResult(blocks, executed_iterations)
    }
  }
}

fn loop(tasks, space, estimate, iteration, limit, state: State) -> State {
  case iteration >= limit {
    True -> state
    False -> {
      let Proposal(selected, proposal_rng) =
        propose(tasks, state.current.blocks, state.rng)
      let candidate_blocks =
        greedy.rebuild(state.current.blocks, selected, space)
      case candidate_blocks == state.current.blocks {
        True ->
          loop(
            tasks,
            space,
            estimate,
            iteration + 1,
            limit,
            State(state.current, state.best, proposal_rng),
          )
        False -> {
          let SearchSpace(_, planning_start, _) = space
          let candidate =
            replace_solution(
              state.current,
              selected,
              candidate_blocks,
              planning_start,
            )
          let #(accepted, acceptance_rng) =
            accept(
              state.current.score,
              candidate.score,
              estimate,
              iteration,
              proposal_rng,
            )
          loop(
            tasks,
            space,
            estimate,
            iteration + 1,
            limit,
            State(
              select_current(state.current, candidate, accepted),
              select_better(state.best, candidate),
              acceptance_rng,
            ),
          )
        }
      }
    }
  }
}

fn replace_solution(
  current: Solution,
  selected: List(scheduling_model.SchedulingTask),
  blocks: List(scheduling_model.ScheduleBlock),
  planning_start: Int,
) -> Solution {
  let replacements = score.contributions(selected, blocks, planning_start)
  let contributions =
    score.replace_contributions(current.contributions, replacements)
  Solution(blocks, score.total(contributions), contributions)
}

fn select_current(current: Solution, candidate: Solution, accepted: Bool) {
  case accepted {
    True -> candidate
    False -> current
  }
}

fn select_better(current: Solution, candidate: Solution) -> Solution {
  case score.compare(candidate.score, current.score) {
    order.Lt -> candidate
    order.Eq | order.Gt -> current
  }
}

fn propose(
  tasks: List(scheduling_model.SchedulingTask),
  blocks: List(scheduling_model.ScheduleBlock),
  rng: Rng,
) -> Proposal {
  let #(target, rng) = choose_target(tasks, blocks, rng)
  propose_after_target(tasks, target, rng)
}

fn choose_target(
  tasks: List(scheduling_model.SchedulingTask),
  blocks: List(scheduling_model.ScheduleBlock),
  rng: Rng,
) {
  let placed = placed_index(blocks)
  let weighted =
    list.map(tasks, fn(task) {
      let minutes = case dict.get(placed, task.id) {
        Ok(value) -> value
        Error(_) -> 0
      }
      let remaining = int.max(0, task.estimate_minutes - minutes)
      #(task, score.priority_weight(task.priority) * remaining)
    })
  let total = list.fold(weighted, 0, fn(value, item) { value + item.1 })
  case total > 0 {
    True -> {
      let #(selected, rng) = deterministic_rng.index(rng, total)
      let assert Ok(target) = weighted_at(weighted, selected)
      #(target, rng)
    }
    False -> {
      let #(selected, rng) = deterministic_rng.index(rng, list.length(tasks))
      let #(target, _) = take_at(tasks, selected, [])
      #(target, rng)
    }
  }
}

fn placed_index(blocks: List(scheduling_model.ScheduleBlock)) {
  list.fold(blocks, dict.new(), fn(index, block) {
    let previous = case dict.get(index, block.task_id) {
      Ok(value) -> value
      Error(_) -> 0
    }
    dict.insert(
      index,
      block.task_id,
      previous + { block.end_seconds - block.start_seconds } / 60,
    )
  })
}

fn weighted_at(items, selected) {
  case items {
    [] -> Error(Nil)
    [#(value, weight), ..rest] ->
      case selected < weight {
        True -> Ok(value)
        False -> weighted_at(rest, selected - weight)
      }
  }
}

fn draw(items: List(a), remaining: Int, rng: Rng, selected: List(a)) {
  case remaining <= 0 || items == [] {
    True -> #(list.reverse(selected), rng)
    False -> {
      let #(index, rng) = deterministic_rng.index(rng, list.length(items))
      let #(value, rest) = take_at(items, index, [])
      draw(rest, remaining - 1, rng, [value, ..selected])
    }
  }
}

fn take_at(items: List(a), index: Int, before: List(a)) -> #(a, List(a)) {
  let assert [first, ..rest] = items
  case index <= 0 {
    True -> #(first, list.append(list.reverse(before), rest))
    False -> take_at(rest, index - 1, [first, ..before])
  }
}

fn coin(rng: Rng) -> #(Bool, Rng) {
  let #(value, rng) = deterministic_rng.index(rng, 2)
  #(value == 1, rng)
}

fn accept(
  current: scheduling_model.Score,
  candidate: scheduling_model.Score,
  estimate: Int,
  iteration: Int,
  rng: Rng,
) -> #(Bool, Rng) {
  let current_primary = current.weighted_unscheduled_minutes
  let candidate_primary = candidate.weighted_unscheduled_minutes
  case int.compare(candidate_primary, current_primary) {
    order.Lt | order.Eq -> #(True, rng)
    order.Gt -> {
      let delta =
        100.0
        *. int.to_float(candidate_primary - current_primary)
        /. int.to_float(estimate)
      let probability = acceptance_probability(delta, temperature(iteration))
      case invalid_probability(probability) {
        True -> #(False, rng)
        False -> {
          let #(sample, rng) = deterministic_rng.uniform(rng)
          #(sample <. probability, rng)
        }
      }
    }
  }
}

fn temperature(iteration: Int) -> Float {
  let progress = int.to_float(iteration) /. int.to_float(search_iterations - 1)
  case float.power(temperature_end /. temperature_start, of: progress) {
    Ok(factor) -> temperature_start *. factor
    Error(_) -> temperature_end
  }
}

fn acceptance_probability(delta_pp: Float, temperature: Float) -> Float {
  float.exponential(0.0 -. delta_pp /. temperature)
}

fn invalid_probability(probability: Float) -> Bool {
  float.compare(probability, with: probability) != order.Eq
  || probability <. 0.0
  || probability >. 1.0
}

fn weighted_estimate(tasks: List(scheduling_model.SchedulingTask)) -> Int {
  list.fold(tasks, 0, fn(total, task) {
    total + score.priority_weight(task.priority) * task.estimate_minutes
  })
}

fn has_actual_unscheduled(
  tasks: List(scheduling_model.SchedulingTask),
  blocks: List(scheduling_model.ScheduleBlock),
) -> Bool {
  let placed = placed_index(blocks)
  list.any(tasks, fn(task) {
    let placed_minutes = case dict.get(placed, task.id) {
      Ok(value) -> value
      Error(_) -> 0
    }
    task.estimate_minutes - placed_minutes > 0
  })
}

fn propose_after_target(
  tasks: List(scheduling_model.SchedulingTask),
  target: scheduling_model.SchedulingTask,
  rng: Rng,
) -> Proposal {
  let #(triple, rng) = coin(rng)
  let count =
    int.min(list.length(tasks), case triple {
      True -> 3
      False -> 2
    })
  let partners = list.filter(tasks, fn(task) { task.id != target.id })
  let #(chosen_partners, rng) = draw(partners, count - 1, rng, [])
  let #(ordered, rng) = draw([target, ..chosen_partners], count, rng, [])
  Proposal(ordered, rng)
}
