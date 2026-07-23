import gleam/dict
import gleam/list
import gleam/order
import gleeunit/should
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score
import tasks/domain/scheduling/simple_sa
import tasks/domain/scheduling/timeline.{AbsoluteInterval, SearchSpace}

fn task(id, estimate, priority, deadline, minimum) {
  scheduling_model.SchedulingTask(
    id,
    estimate,
    priority,
    deadline,
    Spread,
    minimum,
  )
}

fn contended_workload() {
  #(
    [
      task(1, 60, 3, 3600, 30),
      task(2, 90, 5, 5400, 30),
      task(3, 45, 4, 3600, 15),
      task(4, 120, 2, 7200, 30),
      scheduling_model.SchedulingTask(5, 30, 5, 1800, Asap, 30),
    ],
    SearchSpace([AbsoluteInterval(0, 7200)], 0, 0),
  )
}

fn search_seed101(tasks, space) {
  simple_sa.improve(tasks, space, 101)
}

pub fn rebuild_returns_selected_blocks_test() {
  let #(tasks, space) = contended_workload()
  let assert [first, second, ..] = tasks
  let selected = [first, second]
  let initial = greedy.build(tasks, space)
  let #(rebuilt, selected_blocks) = greedy.rebuild(initial, selected, space)

  invariant.validate_generation(rebuilt, tasks, space) |> should.be_ok
  use task <- list.each(selected)
  dict.get(selected_blocks, task.id)
  |> should.equal(
    Ok(list.filter(rebuilt, fn(block) { block.task_id == task.id })),
  )
}

pub fn same_seed_returns_same_search_result_test() {
  let #(tasks, space) = contended_workload()
  search_seed101(tasks, space)
  |> should.equal(search_seed101(tasks, space))
}

pub fn search_result_satisfies_schedule_invariants_test() {
  let #(tasks, space) = contended_workload()
  let result = search_seed101(tasks, space)
  invariant.validate_generation(result.blocks, tasks, space)
  |> should.be_ok
}

pub fn search_never_returns_worse_than_greedy_test() {
  let #(tasks, space) = contended_workload()
  let initial = greedy.build(tasks, space)
  let result = search_seed101(tasks, space)
  let planning_start = 0

  score.compare(
    score.evaluate(tasks, result.blocks, planning_start),
    score.evaluate(tasks, initial, planning_start),
  )
  |> should.not_equal(order.Gt)
}

pub fn empty_input_skips_search_test() {
  let space = SearchSpace([AbsoluteInterval(0, 3600)], 0, 0)
  search_seed101([], space)
  |> should.equal(simple_sa.SearchResult([], 0))
}

pub fn nonpositive_weight_skips_search_test() {
  let space = SearchSpace([AbsoluteInterval(0, 3600)], 0, 0)
  let tasks = [
    scheduling_model.SchedulingTask(1, 60, 0, 3600, Asap, 30),
  ]
  search_seed101(tasks, space)
  |> should.equal(simple_sa.SearchResult(greedy.build(tasks, space), 0))
}

pub fn complete_unimproved_schedule_returns_greedy_result_test() {
  let tasks = [
    scheduling_model.SchedulingTask(1, 60, 3, 3600, Asap, 30),
  ]
  let space = SearchSpace([AbsoluteInterval(0, 3600)], 0, 0)
  let result = search_seed101(tasks, space)

  result.blocks |> should.equal(greedy.build(tasks, space))
}

pub fn complete_unimproved_schedule_stops_after_probe_test() {
  let tasks = [
    scheduling_model.SchedulingTask(1, 60, 3, 3600, Asap, 30),
  ]
  let space = SearchSpace([AbsoluteInterval(0, 3600)], 0, 0)
  let result = search_seed101(tasks, space)

  result.executed_iterations
  |> should.equal(simple_sa.probe_iterations)
}

pub fn incomplete_schedule_uses_full_budget_test() {
  let #(tasks, space) = contended_workload()
  let result = search_seed101(tasks, space)

  result.executed_iterations
  |> should.equal(simple_sa.search_iterations)
}

pub fn probe_improvement_continues_with_full_budget_test() {
  let tasks = [
    scheduling_model.SchedulingTask(1_018_021, 48, 4, 24_060, Spread, 15),
    scheduling_model.SchedulingTask(1_015_967, 82, 3, 20_460, NearDeadline, 15),
    scheduling_model.SchedulingTask(1_013_913, 42, 3, 25_260, Asap, 15),
    scheduling_model.SchedulingTask(1_011_859, 61, 5, 21_780, Asap, 45),
  ]
  let space = SearchSpace([AbsoluteInterval(0, 26_400)], 0, 0)
  let initial = greedy.build(tasks, space)
  let result = search_seed101(tasks, space)

  // The contract is meaningful improvement, not a particular annealing path.
  score.compare(
    score.evaluate(tasks, result.blocks, 0),
    score.evaluate(tasks, initial, 0),
  )
  |> should.equal(order.Lt)
  result.executed_iterations
  |> should.equal(simple_sa.search_iterations)
}

pub fn large_weighted_bound_terminates_with_valid_result_test() {
  // This workload's weighted estimate exceeds one RNG digit.
  let tasks = max_estimate_p5_tasks(256, [])
  let space = SearchSpace([], 0, 0)
  let result = search_seed101(tasks, space)

  invariant.validate_generation(result.blocks, tasks, space)
  |> should.be_ok
}

fn max_estimate_p5_tasks(remaining, acc) {
  case remaining <= 0 {
    True -> acc
    False ->
      max_estimate_p5_tasks(remaining - 1, [
        task(remaining, 525_600, 5, 31_536_000, 1),
        ..acc
      ])
  }
}
