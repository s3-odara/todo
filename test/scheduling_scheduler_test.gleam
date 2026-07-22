import datebook/weekday.{Thursday}
import gleam/list
import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability.{Availability, Interval, WeeklyAvailability}
import tasks/domain/due
import tasks/domain/model.{Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/scheduler
import tasks/domain/scheduling/timeline

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

fn epoch_context() {
  scheduler.context(timestamp.from_unix_seconds(0), duration.seconds(0))
}

fn thursday_availability(intervals) {
  Availability([WeeklyAvailability(Thursday, intervals)], [])
}

pub fn context_preserves_exact_minute_boundary_test() {
  let context =
    scheduler.context(timestamp.from_unix_seconds(-60), duration.seconds(0))
  context.planning_start |> should.equal(timestamp.from_unix_seconds(-60))
}

pub fn context_ceils_partial_minute_test() {
  let context =
    scheduler.context(
      timestamp.from_unix_seconds_and_nanoseconds(seconds: 0, nanoseconds: 1),
      duration.seconds(0),
    )
  context.planning_start |> should.equal(timestamp.from_unix_seconds(60))
}

pub fn context_uses_second_precision_utc_offset_test() {
  let context =
    scheduler.context(timestamp.from_unix_seconds(0), duration.seconds(30))
  context.planning_start |> should.equal(timestamp.from_unix_seconds(30))
}

pub fn same_input_produces_same_generation_test() {
  let availability = thursday_availability([Interval(0, 120)])
  let input = state([task(1, 60, 3)], availability)
  scheduler.generate(input, epoch_context())
  |> should.equal(scheduler.generate(input, epoch_context()))
}

pub fn generation_places_work_inside_availability_test() {
  let availability = thursday_availability([Interval(30, 90)])
  let assert Ok(result) =
    scheduler.generate(state([task(1, 30, 3)], availability), epoch_context())
  let blocks = result.saved_schedule.blocks

  blocks |> should.not_equal([])
  list.all(blocks, fn(block) {
    block.start_seconds >= 30 * 60 && block.end_seconds <= 90 * 60
  })
  |> should.be_true
}

pub fn generation_places_work_before_deadline_test() {
  let availability = thursday_availability([Interval(0, 120)])
  let deadline = 3600
  let input =
    Todo(
      1,
      "task",
      30,
      3,
      Some(due.from_unix_seconds(deadline)),
      Pending,
      Spread,
      30,
    )
  let assert Ok(result) =
    scheduler.generate(state([input], availability), epoch_context())

  list.all(result.saved_schedule.blocks, fn(block) {
    block.end_seconds <= deadline
  })
  |> should.be_true
}

pub fn priority_is_the_primary_objective_test() {
  let availability = thursday_availability([Interval(0, 60)])
  let assert Ok(scheduling_model.GenerationResult(
    scheduling_model.SavedSchedule(blocks: [only], ..),
    report,
  )) =
    scheduler.generate(
      state([task(1, 60, 1), task(2, 60, 5)], availability),
      epoch_context(),
    )

  only.task_id |> should.equal(2)
  report.unscheduled
  |> should.equal([scheduling_model.UnscheduledTask(1, 60)])
}

pub fn policy_is_the_secondary_objective_test() {
  let availability = thursday_availability([Interval(0, 120)])
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
  )) = scheduler.generate(state([asap], availability), epoch_context())
  let assert Ok(scheduling_model.GenerationResult(
    scheduling_model.SavedSchedule(blocks: [near_block], ..),
    _,
  )) = scheduler.generate(state([near], availability), epoch_context())

  let ordered = asap_block.start_seconds < near_block.start_seconds
  ordered |> should.be_true
}

pub fn empty_availability_reports_unscheduled_tasks_in_stable_order_test() {
  let assert Ok(scheduling_model.GenerationResult(
    scheduling_model.SavedSchedule(blocks: [], ..),
    report,
  )) =
    scheduler.generate(
      state([task(2, 30, 3), task(1, 60, 5)], Availability([], [])),
      epoch_context(),
    )

  report.unscheduled
  |> should.equal([
    scheduling_model.UnscheduledTask(1, 60),
    scheduling_model.UnscheduledTask(2, 30),
  ])
}

pub fn oversized_projection_returns_scheduler_error_test() {
  let intervals =
    list.repeat(Interval(0, 1), timeline.projected_interval_limit + 1)
  let result =
    scheduler.generate(
      state([task(1, 30, 3)], thursday_availability(intervals)),
      epoch_context(),
    )

  result |> should.equal(Error(scheduler.SearchSpaceTooLarge))
}
