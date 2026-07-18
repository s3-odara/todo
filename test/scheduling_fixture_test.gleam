import gleam/int
import gleam/list
import gleeunit/should
import scheduling_fixture
import tasks/domain/scheduling/model.{type SchedulingTask}

const fixture_path = "benchmark/fixtures/representative-workloads-v1.json"

pub fn representative_fixture_loads_and_expands_test() {
  let assert Ok(corpus) = scheduling_fixture.load(fixture_path)
  let scheduling_fixture.FixtureCorpus(base, permutations) = corpus
  list.length(base) |> should.equal(6)
  list.length(permutations) |> should.equal(24)
  base
  |> list.fold(0, fn(total, scenario) { total + list.length(scenario.tasks) })
  |> should.equal(152)
  permutations
  |> list.fold(0, fn(total, scenario) { total + list.length(scenario.tasks) })
  |> should.equal(608)

  let normal = find_scenario(base, "normal_office_two_weeks")
  list.length(normal.tasks) |> should.equal(24)
  list.length(normal.projected) |> should.equal(20)
  let assert [first_task, ..] = normal.tasks
  first_task.deadline_seconds |> should.equal(180 * 60)
  let assert [first_interval, ..] = normal.projected
  first_interval.start |> should.equal(0)
  first_interval.end |> should.equal(180 * 60)
}

pub fn lowbias_permutations_are_reproducible_and_preserve_workload_test() {
  let assert Ok(first) = scheduling_fixture.load(fixture_path)
  let assert Ok(second) = scheduling_fixture.load(fixture_path)
  first |> should.equal(second)
  let scheduling_fixture.FixtureCorpus(base_scenarios, permutations) = first

  let base = find_scenario(base_scenarios, "overloaded_release_week")
  let permuted =
    find_scenario(permutations, "overloaded_release_week__id_lowbias_101")
  task_ids(base.tasks)
  |> list.sort(by: int.compare)
  |> should.equal(task_ids(permuted.tasks) |> list.sort(by: int.compare))
  task_ids(base.tasks) |> should.not_equal(task_ids(permuted.tasks))
  task_shapes(base.tasks) |> should.equal(task_shapes(permuted.tasks))
}

pub fn adversarial_permutation_preserves_workload_test() {
  let assert Ok(corpus) = scheduling_fixture.load(fixture_path)
  let scheduling_fixture.FixtureCorpus(base_scenarios, permutations) = corpus
  let base = find_scenario(base_scenarios, "meeting_fragmented_week")
  let adversarial =
    find_scenario(permutations, "meeting_fragmented_week__id_adversarial")
  task_ids(base.tasks)
  |> list.sort(by: int.compare)
  |> should.equal(task_ids(adversarial.tasks) |> list.sort(by: int.compare))
  task_shapes(base.tasks) |> should.equal(task_shapes(adversarial.tasks))
}

fn find_scenario(
  scenarios: List(scheduling_fixture.FixtureScenario),
  name: String,
) {
  let assert Ok(scenario) =
    list.find(scenarios, fn(scenario) { scenario.name == name })
  scenario
}

fn task_ids(tasks: List(SchedulingTask)) {
  list.map(tasks, fn(task) { task.id })
}

fn task_shapes(tasks: List(SchedulingTask)) {
  list.map(tasks, fn(task) {
    #(
      task.estimate_minutes,
      task.priority,
      task.deadline_seconds,
      task.scheduling_policy,
      task.minimum_split_minutes,
    )
  })
}
