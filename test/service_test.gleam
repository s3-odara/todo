import gleam/option.{None, Some}
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability
import tasks/domain/due
import tasks/domain/filter.{
  AllScheduled, AllStatuses, DueWindow, ListFilter, PendingOnly, ScheduledDate,
  ScheduledExact, Today,
}
import tasks/domain/model.{
  AlreadyDone, Done, NotFound, Pending, Todo, ValidatedAdd,
}
import tasks/domain/policy.{Spread}
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/scheduler
import todo_app/service
import todo_app/store.{Store}

fn state_with(tasks) {
  AppState(tasks, availability.empty(), None)
}

fn store_with(tasks) {
  Store(fn() { Ok(state_with(tasks)) }, fn(_) { Ok(Nil) })
}

fn state_with_schedule(tasks, schedule) {
  AppState(tasks, availability.empty(), Some(schedule))
}

fn saved_schedule() {
  let instant = timestamp.from_unix_seconds(1_768_173_540)
  scheduling_model.SavedSchedule(instant, instant, 32_400, [])
}

fn due_at(value) {
  let assert Ok(value) = due.input(value, calendar.utc_offset)
  value
}

fn now() {
  due.instant(due_at("2026-07-24T12:00"))
}

fn pending_filter() {
  ListFilter(PendingOnly, None)
  |> filter.resolve(now(), calendar.utc_offset)
}

fn pending_due(id, title, canonical) {
  Todo(id, title, 0, 3, Some(due_at(canonical)), Pending, Spread, 30)
}

pub fn add_saves_and_returns_the_added_task_test() {
  let existing = Todo(1, "old", 0, 3, None, Pending, Spread, 30)
  let added = Todo(2, "new", 0, 3, None, Pending, Spread, 30)
  let store =
    Store(fn() { Ok(state_with([existing])) }, fn(state) {
      state.tasks |> should.equal([added, existing])
      Ok(Nil)
    })

  service.add(store, ValidatedAdd("new", 0, 3, None, Spread, 30))
  |> should.equal(Ok(added))
}

pub fn add_preserves_the_current_schedule_test() {
  let schedule = saved_schedule()
  let store =
    Store(fn() { Ok(state_with_schedule([], schedule)) }, fn(state) {
      state.current_schedule |> should.equal(Some(schedule))
      Ok(Nil)
    })

  service.add(store, ValidatedAdd("x", 0, 3, None, Spread, 30))
  |> should.be_ok
}

pub fn an_add_load_failure_is_reported_test() {
  let store =
    Store(fn() { Error("corrupt") }, fn(_) { Error("save must not run") })

  service.add(store, ValidatedAdd("x", 0, 3, None, Spread, 30))
  |> should.equal(Error(service.Persisted("corrupt")))
}

pub fn an_add_save_failure_is_reported_test() {
  let store = Store(fn() { Ok(state_with([])) }, fn(_) { Error("disk") })

  service.add(store, ValidatedAdd("x", 0, 3, None, Spread, 30))
  |> should.equal(Error(service.Persisted("disk")))
}

pub fn done_does_not_match_an_id_prefix_test() {
  let ten = Todo(10, "ten", 0, 3, None, Pending, Spread, 30)
  let hundred = Todo(100, "one hundred", 0, 3, None, Pending, Spread, 30)

  service.done(store_with([ten, hundred]), 1)
  |> should.equal(Error(service.Domain(NotFound)))
}

pub fn done_saves_and_returns_the_completed_task_test() {
  let ten = Todo(10, "ten", 0, 3, None, Pending, Spread, 30)
  let hundred = Todo(100, "one hundred", 0, 3, None, Pending, Spread, 30)
  let store =
    Store(fn() { Ok(state_with([ten, hundred])) }, fn(state) {
      state.tasks
      |> should.equal([Todo(10, "ten", 0, 3, None, Done, Spread, 30), hundred])
      Ok(Nil)
    })

  service.done(store, 10)
  |> should.equal(Ok(Todo(10, "ten", 0, 3, None, Done, Spread, 30)))
}

pub fn done_preserves_the_current_schedule_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending, Spread, 30)
  let schedule = saved_schedule()
  let store =
    Store(fn() { Ok(state_with_schedule([pending], schedule)) }, fn(state) {
      state.current_schedule |> should.equal(Some(schedule))
      Ok(Nil)
    })

  service.done(store, 1) |> should.be_ok
}

pub fn list_returns_pending_tasks_without_saving_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending, Spread, 30)
  let completed = Todo(2, "y", 0, 3, None, Done, Spread, 30)
  let store =
    Store(fn() { Ok(state_with([pending, completed])) }, fn(_) {
      Error("save must not run")
    })

  service.list(store, pending_filter()) |> should.equal(Ok([pending]))
}

pub fn list_propagates_the_due_filter_test() {
  let undated = Todo(1, "undated", 0, 3, None, Pending, Spread, 30)
  let dated = pending_due(2, "dated", "2026-07-24T12:00")

  service.list(
    store_with([undated, dated]),
    filter.resolve(
      ListFilter(PendingOnly, Some(Today)),
      now(),
      calendar.utc_offset,
    ),
  )
  |> should.equal(Ok([dated]))
}

pub fn a_list_load_failure_is_reported_test() {
  let store =
    Store(fn() { Error("corrupt") }, fn(_) { Error("save must not run") })

  service.list(store, pending_filter())
  |> should.equal(Error(service.Persisted("corrupt")))
}

pub fn a_missing_task_is_not_saved_test() {
  let task = Todo(1, "x", 0, 3, None, Pending, Spread, 30)
  let store =
    Store(fn() { Ok(state_with([task])) }, fn(_) { Error("save must not run") })

  service.done(store, 99)
  |> should.equal(Error(service.Domain(NotFound)))
}

pub fn an_already_completed_task_is_not_saved_test() {
  let completed = Todo(2, "y", 0, 3, None, Done, Spread, 30)
  let store =
    Store(fn() { Ok(state_with([completed])) }, fn(_) {
      Error("save must not run")
    })

  service.done(store, 2)
  |> should.equal(Error(service.Domain(AlreadyDone)))
}

pub fn availability_mutation_preserves_tasks_and_schedule_test() {
  let schedule = saved_schedule()
  let task = Todo(1, "x", 0, 3, None, Pending, Spread, 30)
  let store =
    Store(fn() { Ok(state_with_schedule([task], schedule)) }, fn(state) {
      state.tasks |> should.equal([task])
      state.current_schedule |> should.equal(Some(schedule))
      state.availability
      |> should.equal(
        availability.Availability(
          [
            availability.WeeklyAvailability(availability.Mon, [
              availability.Interval(540, 720),
            ]),
          ],
          [],
        ),
      )
      Ok(Nil)
    })

  service.mutate_availability(
    store,
    availability.AddWeekly([availability.Mon], availability.Interval(540, 720)),
  )
  |> should.equal(Ok(Nil))
}

pub fn availability_save_failure_is_reported_test() {
  let store = Store(fn() { Ok(state_with([])) }, fn(_) { Error("disk") })
  service.mutate_availability(
    store,
    availability.AddWeekly([availability.Mon], availability.Interval(540, 720)),
  )
  |> should.equal(Error(service.Persisted("disk")))
}

pub fn reset_without_an_override_is_a_noop_and_does_not_save_test() {
  let store =
    Store(fn() { Ok(state_with([])) }, fn(_) { panic as "save must not run" })
  let assert Ok(date) = due.parse_date("2026-07-20")
  service.mutate_availability(store, availability.ResetDate(date))
  |> should.equal(Ok(Nil))
}

pub fn availability_list_does_not_save_test() {
  let state = state_with([])
  let store = Store(fn() { Ok(state) }, fn(_) { panic as "save must not run" })
  service.availability_list(store)
  |> should.equal(Ok(availability.empty()))
}

pub fn scheduled_list_joins_current_task_status_without_saving_test() {
  let offset = duration.hours(9)
  let start =
    timestamp.from_calendar(
      calendar.Date(2026, calendar.July, 24),
      calendar.TimeOfDay(9, 0, 0, 0),
      offset,
    )
  let end = timestamp.add(start, duration.minutes(60))
  let #(start_seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(start)
  let #(end_seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(end)
  let task = Todo(1, "current title", 60, 3, None, Done, Spread, 30)
  let schedule =
    scheduling_model.SavedSchedule(start, start, 32_400, [
      scheduling_model.ScheduleBlock(1, start_seconds, end_seconds),
    ])
  let store =
    Store(fn() { Ok(state_with_schedule([task], schedule)) }, fn(_) {
      panic as "save must not run"
    })

  service.scheduled_list(store, AllStatuses, AllScheduled, None)
  |> should.equal(
    Ok(
      service.ScheduledListing(32_400, [
        service.ScheduledItem(
          scheduling_model.ScheduleBlock(1, start_seconds, end_seconds),
          task,
        ),
      ]),
    ),
  )
  service.scheduled_list(
    store,
    PendingOnly,
    ScheduledExact(ScheduledDate(calendar.Date(2026, calendar.July, 24))),
    None,
  )
  |> should.equal(Ok(service.ScheduledListing(32_400, [])))
}

pub fn scheduled_overlap_uses_half_open_bounds_with_negative_seconds_test() {
  let window =
    Some(DueWindow(
      Some(timestamp.from_unix_seconds(0)),
      Some(timestamp.from_unix_seconds(86_400)),
    ))

  // Ending exactly at the lower bound and starting exactly at the exclusive
  // upper bound do not overlap.
  filter.block_overlaps(-60, 0, window) |> should.be_false
  filter.block_overlaps(86_400, 86_460, window) |> should.be_false

  // Crossing either boundary overlaps; the first case also fixes negative Unix
  // second handling at the service/filter boundary.
  filter.block_overlaps(-60, 60, window) |> should.be_true
  filter.block_overlaps(86_340, 86_460, window) |> should.be_true
}

pub fn generate_schedule_replaces_snapshot_and_saves_report_only_in_result_test() {
  let now =
    timestamp.from_calendar(
      calendar.Date(2026, calendar.July, 24),
      calendar.TimeOfDay(12, 0, 1, 0),
      calendar.utc_offset,
    )
  let task =
    Todo(1, "x", 60, 3, Some(due_at("2026-07-25T12:00")), Pending, Spread, 30)
  let old = saved_schedule()
  let store =
    Store(fn() { Ok(state_with_schedule([task], old)) }, fn(state) {
      state.current_schedule |> should.not_equal(Some(old))
      let assert Some(saved) = state.current_schedule
      saved.blocks |> should.equal([])
      Ok(Nil)
    })

  let assert Ok(result) =
    service.generate_schedule(
      store,
      scheduler.context(now, calendar.utc_offset),
    )
  result.report.unscheduled
  |> should.equal([scheduling_model.UnscheduledTask(1, 60)])
}

pub fn a_done_save_failure_is_reported_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending, Spread, 30)
  let store =
    Store(fn() { Ok(state_with([pending])) }, fn(_) { Error("rename") })

  service.done(store, 1)
  |> should.equal(Error(service.Persisted("rename")))
}
