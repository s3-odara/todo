import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability.{
  Availability, Interval, Thu, WeeklyAvailability,
}
import tasks/domain/due
import tasks/domain/model.{Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/move
import tasks/domain/scheduling/scheduler
import tasks/domain/scheduling/timeline.{AbsoluteInterval}

fn state(tasks, availability) {
  AppState(1, tasks, availability, None)
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

pub fn context_rounds_exact_negative_nanosecond_and_second_offset_test() {
  let exact =
    scheduler.context(timestamp.from_unix_seconds(-60), duration.seconds(0))
  invariant.seconds(exact.planning_start) |> should.equal(-60)

  let partial =
    scheduler.context(
      timestamp.from_unix_seconds_and_nanoseconds(seconds: 0, nanoseconds: 1),
      duration.seconds(0),
    )
  invariant.seconds(partial.planning_start) |> should.equal(60)

  let odd_offset =
    scheduler.context(timestamp.from_unix_seconds(0), duration.seconds(30))
  invariant.seconds(odd_offset.planning_start) |> should.equal(30)
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
    [task(1, 60, 3)],
    [AbsoluteInterval(0, 7200)],
    0,
    0,
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
  let ordered =
    invariant.seconds(asap_block.start) < invariant.seconds(near_block.start)
  ordered |> should.be_true
}

pub fn kind_specific_generators_and_atomic_apply_test() {
  let projected = [AbsoluteInterval(0, 10_800)]
  let tasks = [
    Todo(
      1,
      "one",
      120,
      3,
      Some(due.from_unix_seconds(10_800)),
      Pending,
      Spread,
      30,
    ),
    Todo(
      2,
      "two",
      120,
      3,
      Some(due.from_unix_seconds(10_800)),
      Pending,
      Spread,
      30,
    ),
  ]
  let a =
    scheduling_model.ScheduleBlock(
      1,
      timestamp.from_unix_seconds(0),
      timestamp.from_unix_seconds(3600),
    )
  let b =
    scheduling_model.ScheduleBlock(
      2,
      timestamp.from_unix_seconds(3600),
      timestamp.from_unix_seconds(5400),
    )
  let has_add = move.add_candidates([], tasks, projected, 0, 0) != []
  has_add |> should.be_true
  let has_relocate = move.relocate_candidates([a], tasks, projected, 0, 0) != []
  has_relocate |> should.be_true
  let has_swap = move.swap_candidates([a, b], tasks) != []
  has_swap |> should.be_true
  let has_split = move.split_candidates([a], tasks, projected, 0, 0) != []
  has_split |> should.be_true
  let a2 =
    scheduling_model.ScheduleBlock(
      1,
      timestamp.from_unix_seconds(5400),
      timestamp.from_unix_seconds(7200),
    )
  let has_merge = move.merge_candidates([a, a2], tasks, projected, 0, 0) != []
  has_merge |> should.be_true
  move.apply_repack(
    [],
    move.Repack(move.Relocate, [a], [b]),
    tasks,
    projected,
    0,
    0,
  )
  |> should.be_error
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
