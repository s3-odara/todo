import gleam/list
import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability.{Availability, Interval, WeeklyAvailability}
import tasks/domain/due
import tasks/domain/local_time.{Thu}
import tasks/domain/model.{type Todo, Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/scheduler
import tasks/domain/scheduling/timeline.{AbsoluteInterval, SearchSpace}
import tasks/runtime/parallel

pub fn parallel_runtime_worker_count_and_reduction_test() {
  let schedulers = parallel.online_scheduler_count()
  let at_least_one = schedulers >= 1
  at_least_one |> should.be_true
  parallel.worker_count(8, 0) |> should.equal(0)
  parallel.worker_count(8, 1) |> should.equal(1)
  parallel.worker_count(8, 3) |> should.equal(3)
  parallel.worker_count(2, 8) |> should.equal(2)
  parallel.worker_count(0, 3) |> should.equal(1)

  let sum = fn(values) {
    list.fold(values, 0, fn(total, value) { total + value })
  }
  parallel.map_chunks_reduce([], 0, sum, fn(a, b) { a + b })
  |> should.equal(0)
  parallel.map_chunks_reduce([1], 0, sum, fn(a, b) { a + b })
  |> should.equal(1)
  parallel.map_chunks_reduce([1, 2, 3, 4], 0, sum, fn(a, b) { a + b })
  |> should.equal(10)
}

fn state(tasks, availability) {
  AppState(tasks, availability, None)
}

fn task(id, estimate, priority) {
  Todo(
    id,
    "task",
    estimate,
    priority,
    Some(due.from_unix_seconds(7200)),
    Pending,
    Spread,
    30,
  )
}

fn scheduling_task(task: Todo) -> scheduling_model.SchedulingTask {
  let assert Some(deadline) = task.due
  scheduling_model.SchedulingTask(
    task.id,
    task.estimate_minutes,
    task.priority,
    due.to_unix_seconds(deadline),
    task.scheduling_policy,
    task.minimum_split_minutes,
  )
}

pub fn context_rounds_exact_negative_nanosecond_and_second_offset_test() {
  let exact =
    scheduler.context(timestamp.from_unix_seconds(-60), duration.seconds(0))
  exact.planning_start |> should.equal(timestamp.from_unix_seconds(-60))

  let partial =
    scheduler.context(
      timestamp.from_unix_seconds_and_nanoseconds(seconds: 0, nanoseconds: 1),
      duration.seconds(0),
    )
  partial.planning_start |> should.equal(timestamp.from_unix_seconds(60))

  let odd_offset =
    scheduler.context(timestamp.from_unix_seconds(0), duration.seconds(30))
  odd_offset.planning_start |> should.equal(timestamp.from_unix_seconds(30))
}

pub fn deterministic_generation_respects_availability_test() {
  let availability =
    Availability([WeeklyAvailability(Thu, [Interval(0, 120)])], [])
  let context =
    scheduler.context(timestamp.from_unix_seconds(0), duration.seconds(0))
  let first = scheduler.generate(state([task(1, 60, 3)], availability), context)
  let second =
    scheduler.generate(state([task(1, 60, 3)], availability), context)
  first |> should.equal(second)
  let assert Ok(scheduling_model.GenerationResult(
    scheduling_model.SavedSchedule(blocks: blocks, ..),
    scheduling_model.GenerationReport(unscheduled: [], excluded: []),
  )) = first
  let nonempty = blocks != []
  nonempty |> should.be_true
  invariant.validate_generation(
    blocks,
    [scheduling_task(task(1, 60, 3))],
    SearchSpace([AbsoluteInterval(0, 7200)], 0, 0),
  )
  |> should.be_ok
}

pub fn priority_is_the_primary_objective_test() {
  let availability =
    Availability([WeeklyAvailability(Thu, [Interval(0, 60)])], [])
  let context =
    scheduler.context(timestamp.from_unix_seconds(0), duration.seconds(0))
  let assert Ok(scheduling_model.GenerationResult(
    scheduling_model.SavedSchedule(blocks: [only], ..),
    report,
  )) =
    scheduler.generate(
      state([task(1, 60, 1), task(2, 60, 5)], availability),
      context,
    )
  only.task_id |> should.equal(2)
  report.unscheduled
  |> should.equal([scheduling_model.UnscheduledTask(1, 60)])
}

pub fn policy_secondary_objective_moves_work_earlier_or_later_test() {
  let availability =
    Availability([WeeklyAvailability(Thu, [Interval(0, 120)])], [])
  let context =
    scheduler.context(timestamp.from_unix_seconds(0), duration.seconds(0))
  let asap =
    Todo(1, "asap", 30, 3, Some(due.from_unix_seconds(7200)), Pending, Asap, 30)
  let near =
    Todo(
      1,
      "near",
      30,
      3,
      Some(due.from_unix_seconds(7200)),
      Pending,
      NearDeadline,
      30,
    )
  let assert Ok(scheduling_model.GenerationResult(
    scheduling_model.SavedSchedule(blocks: [asap_block], ..),
    _,
  )) = scheduler.generate(state([asap], availability), context)
  let assert Ok(scheduling_model.GenerationResult(
    scheduling_model.SavedSchedule(blocks: [near_block], ..),
    _,
  )) = scheduler.generate(state([near], availability), context)
  let ordered = asap_block.start_seconds < near_block.start_seconds
  ordered |> should.be_true
}

pub fn empty_availability_reports_all_unscheduled_test() {
  let context =
    scheduler.context(timestamp.from_unix_seconds(0), duration.seconds(0))
  let assert Ok(scheduling_model.GenerationResult(
    scheduling_model.SavedSchedule(blocks: [], ..),
    report,
  )) =
    scheduler.generate(state([task(1, 60, 5)], Availability([], [])), context)
  report.unscheduled
  |> should.equal([scheduling_model.UnscheduledTask(1, 60)])
}
