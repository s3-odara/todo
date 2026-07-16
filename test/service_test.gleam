import gleam/option.{None, Some}
import gleam/time/calendar
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability
import tasks/domain/due
import tasks/domain/filter.{ListFilter, PendingOnly, Today}
import tasks/domain/model.{
  AlreadyDone, Done, NotFound, Pending, Todo, ValidatedAdd,
}
import tasks/domain/policy.{Spread}
import tasks/domain/scheduling/model as scheduling_model
import todo_app/service
import todo_app/store.{Store}

fn state_with(tasks) {
  AppState(1, tasks, availability.empty(), None)
}

fn store_with(tasks) {
  Store(fn() { Ok(state_with(tasks)) }, fn(_) { Ok(Nil) })
}

fn state_with_schedule(tasks, schedule) {
  AppState(1, tasks, availability.empty(), Some(schedule))
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

pub fn a_done_save_failure_is_reported_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending, Spread, 30)
  let store =
    Store(fn() { Ok(state_with([pending])) }, fn(_) { Error("rename") })

  service.done(store, 1)
  |> should.equal(Error(service.Persisted("rename")))
}
