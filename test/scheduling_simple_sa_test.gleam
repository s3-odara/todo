import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/time/duration
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability.{Availability, Interval, WeeklyAvailability}
import tasks/domain/due
import tasks/domain/local_time.{Thu}
import tasks/domain/model.{Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/deterministic_rng
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/scheduler
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

fn workload() {
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

fn improve_seed101(tasks, space) {
  simple_sa.improve(tasks, space, 101, simple_sa.scenario_identity(tasks))
}

fn reproduce_seed101(tasks, space) {
  #(improve_seed101(tasks, space), improve_seed101(tasks, space))
}

fn incomplete_contention_tasks() {
  [
    scheduling_model.SchedulingTask(1, 120, 1, 7200, Asap, 30),
    task(2, 180, 5, 21_600, 30),
    scheduling_model.SchedulingTask(3, 90, 4, 14_400, NearDeadline, 30),
    task(4, 120, 3, 21_600, 30),
  ]
}

fn incomplete_contention_blocks() {
  [
    scheduling_model.ScheduleBlock(4, 0, 1800),
    scheduling_model.ScheduleBlock(2, 1800, 9000),
    scheduling_model.ScheduleBlock(3, 9000, 14_400),
    scheduling_model.ScheduleBlock(2, 14_400, 18_000),
  ]
}

fn scheduler_seed_tasks() {
  [
    scheduling_model.SchedulingTask(1, 100, 2, 26_160, NearDeadline, 30),
    scheduling_model.SchedulingTask(2, 137, 5, 31_980, Spread, 45),
    scheduling_model.SchedulingTask(3, 53, 3, 37_800, Asap, 15),
    scheduling_model.SchedulingTask(4, 90, 1, 43_620, NearDeadline, 30),
    scheduling_model.SchedulingTask(5, 127, 4, 49_440, Spread, 45),
    scheduling_model.SchedulingTask(6, 43, 2, 15_600, Asap, 15),
    scheduling_model.SchedulingTask(7, 80, 5, 21_420, NearDeadline, 30),
    scheduling_model.SchedulingTask(8, 117, 3, 27_240, Spread, 45),
    scheduling_model.SchedulingTask(9, 33, 1, 33_060, Asap, 15),
    scheduling_model.SchedulingTask(10, 70, 4, 38_880, NearDeadline, 30),
    scheduling_model.SchedulingTask(11, 107, 2, 44_700, Spread, 45),
    scheduling_model.SchedulingTask(12, 144, 5, 10_860, Asap, 15),
  ]
}

fn scheduler_seed_state() {
  let todos =
    scheduler_seed_tasks()
    |> list.map(fn(task) {
      Todo(
        task.id,
        "task",
        task.estimate_minutes,
        task.priority,
        Some(due.from_unix_seconds(task.deadline_seconds)),
        Pending,
        task.scheduling_policy,
        task.minimum_split_minutes,
      )
    })
  AppState(
    todos,
    Availability(
      [
        WeeklyAvailability(Thu, [
          Interval(0, 240),
          Interval(300, 540),
          Interval(600, 840),
        ]),
      ],
      [],
    ),
    None,
  )
}

pub fn scheduler_generate_matches_literal_seed101_result_and_repeats_test() {
  let epoch = timestamp.from_unix_seconds(0)
  let context = scheduler.context(epoch, duration.seconds(0))
  let expected_blocks = [
    scheduling_model.ScheduleBlock(12, 0, 8640),
    scheduling_model.ScheduleBlock(6, 8640, 9600),
    scheduling_model.ScheduleBlock(7, 9600, 14_400),
    scheduling_model.ScheduleBlock(3, 18_000, 19_980),
    scheduling_model.ScheduleBlock(2, 19_980, 28_200),
    scheduling_model.ScheduleBlock(10, 28_200, 32_400),
    scheduling_model.ScheduleBlock(3, 36_000, 37_200),
    scheduling_model.ScheduleBlock(11, 37_200, 42_420),
    scheduling_model.ScheduleBlock(5, 42_420, 49_440),
  ]
  let expected =
    scheduling_model.GenerationResult(
      scheduling_model.SavedSchedule(epoch, epoch, 0, expected_blocks),
      scheduling_model.GenerationReport(
        [
          scheduling_model.UnscheduledTask(1, 100),
          scheduling_model.UnscheduledTask(4, 90),
          scheduling_model.UnscheduledTask(5, 10),
          scheduling_model.UnscheduledTask(6, 27),
          scheduling_model.UnscheduledTask(8, 117),
          scheduling_model.UnscheduledTask(9, 33),
          scheduling_model.UnscheduledTask(11, 20),
        ],
        [],
      ),
    )
  let assert Ok(first) = scheduler.generate(scheduler_seed_state(), context)
  let assert Ok(repeat) = scheduler.generate(scheduler_seed_state(), context)
  first |> should.equal(expected)
  repeat |> should.equal(first)
  score.evaluate(scheduler_seed_tasks(), first.saved_schedule.blocks, 0)
  |> should.equal(scheduling_model.Score(965, 9.334134963074609))
}

pub fn same_seed_reproducible_valid_and_never_worse_test() {
  let #(tasks, space) = workload()
  let initial = greedy.build(tasks, space)
  let #(first, repeat) = reproduce_seed101(tasks, space)
  first |> should.equal(repeat)
  invariant.validate_generation(first, tasks, space) |> should.be_ok
  let not_worse =
    score.compare(
      score.evaluate(tasks, first, 0),
      score.evaluate(tasks, initial, 0),
    )
    != order.Gt
  not_worse |> should.be_true
  simple_sa.search_iterations |> should.equal(16_384)
  simple_sa.probe_iterations |> should.equal(1024)
}

pub fn empty_and_nonpositive_weight_inputs_return_greedy_test() {
  let space = SearchSpace([AbsoluteInterval(0, 3600)], 0, 0)
  improve_seed101([], space) |> should.equal([])

  let tasks = [
    scheduling_model.SchedulingTask(1, 60, 0, 3600, Asap, 30),
  ]
  improve_seed101(tasks, space) |> should.equal(greedy.build(tasks, space))
}

pub fn full_placement_without_improvement_returns_greedy_test() {
  let tasks = [
    scheduling_model.SchedulingTask(1, 60, 3, 3600, Asap, 30),
  ]
  let space = SearchSpace([AbsoluteInterval(0, 3600)], 0, 0)
  improve_seed101(tasks, space) |> should.equal(greedy.build(tasks, space))
}

pub fn full_placement_probe_improvement_preserves_full_chain_result_test() {
  let tasks = [
    scheduling_model.SchedulingTask(1_018_021, 48, 4, 24_060, Spread, 15),
    scheduling_model.SchedulingTask(1_015_967, 82, 3, 20_460, NearDeadline, 15),
    scheduling_model.SchedulingTask(1_013_913, 42, 3, 25_260, Asap, 15),
    scheduling_model.SchedulingTask(1_011_859, 61, 5, 21_780, Asap, 45),
  ]
  let space = SearchSpace([AbsoluteInterval(0, 26_400)], 0, 0)
  let initial = greedy.build(tasks, space)
  let expected_full_chain = [
    scheduling_model.ScheduleBlock(1_011_859, 4080, 7740),
    scheduling_model.ScheduleBlock(1_013_913, 7740, 10_260),
    scheduling_model.ScheduleBlock(1_018_021, 10_260, 13_140),
    scheduling_model.ScheduleBlock(1_015_967, 13_140, 18_060),
  ]
  let improved = improve_seed101(tasks, space)
  score.evaluate(tasks, initial, 0).weighted_unscheduled_minutes
  |> should.equal(0)
  score.compare(
    score.evaluate(tasks, expected_full_chain, 0),
    score.evaluate(tasks, initial, 0),
  )
  |> should.equal(order.Lt)
  improved |> should.equal(expected_full_chain)
}

pub fn incomplete_seed101_preserves_locked_full_chain_result_test() {
  let tasks = incomplete_contention_tasks()
  let blocks =
    improve_seed101(tasks, SearchSpace([AbsoluteInterval(0, 18_000)], 0, 0))
  blocks |> should.equal(incomplete_contention_blocks())
  score.evaluate(tasks, blocks, 0)
  |> should.equal(scheduling_model.Score(480, 1.6070023148148147))
}

pub fn rng_stream_identity_and_bounds_test() {
  let #(a, _) = deterministic_rng.next(deterministic_rng.for_scenario(101, 77))
  let #(b, _) = deterministic_rng.next(deterministic_rng.for_scenario(101, 78))
  let different = a != b
  different |> should.be_true
  let values = rng_values(2000, deterministic_rng.new(41), [])
  list.all(values, fn(value) { value >= 0 && value < 7 })
  |> should.be_true

  let single_digit_domain = 2_147_483_646
  let #(legacy_boundary, _) =
    deterministic_rng.index(deterministic_rng.new(41), single_digit_domain)
  legacy_boundary |> should.equal(2_027_381)
  let bounds = [
    single_digit_domain,
    single_digit_domain + 1,
    4_611_686_009_837_453_317,
  ]
  list.each(bounds, fn(bound) {
    let #(first, _) = deterministic_rng.index(deterministic_rng.new(41), bound)
    let #(repeat, _) = deterministic_rng.index(deterministic_rng.new(41), bound)
    first |> should.equal(repeat)
    let in_range = first >= 0 && first < bound
    in_range |> should.be_true
  })
}

pub fn large_weighted_bound_terminates_valid_and_reproduces_test() {
  let tasks = max_estimate_p5_tasks(256, [])
  let total = 256 * 525_600 * 16
  let exceeds_single_digit_domain = total > 2_147_483_646
  exceeds_single_digit_domain |> should.be_true
  let space = SearchSpace([], 0, 0)
  let #(first, repeat) = reproduce_seed101(tasks, space)
  first |> should.equal(repeat)
  first |> should.equal([])
  invariant.validate_generation(first, tasks, space) |> should.be_ok
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

fn rng_values(remaining, rng, acc) {
  case remaining <= 0 {
    True -> acc
    False -> {
      let #(value, rng) = deterministic_rng.index(rng, 7)
      rng_values(remaining - 1, rng, [value, ..acc])
    }
  }
}
