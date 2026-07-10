import gleam/option.{None}
import gleeunit/should
import tasks/domain/model.{
  AddRequest, AlreadyDone, Done, DoneRequest, InvalidInput, ListRequest,
  NotFound, Pending, Todo,
}
import todo_app/service
import todo_app/store.{Store}

fn store_with(tasks) {
  Store(fn() { Ok(tasks) }, fn(_) { Ok(Nil) })
}

fn inaccessible_store() {
  Store(fn() { Error("load must not run") }, fn(_) {
    Error("save must not run")
  })
}

pub fn invalid_add_is_rejected_without_accessing_persistence_test() {
  service.add(inaccessible_store(), AddRequest("bad\n", "0m", "3", None))
  |> should.equal(Error(service.Domain(InvalidInput)))
}

pub fn invalid_done_is_rejected_without_accessing_persistence_test() {
  service.done(inaccessible_store(), DoneRequest("01"))
  |> should.equal(Error(service.Domain(InvalidInput)))
}

pub fn adding_a_task_uses_the_next_id_test() {
  let existing = Todo(2_147_483_647, "old", 0, 3, None, Done)

  service.add(store_with([existing]), AddRequest("new", "0m", "3", None))
  |> should.equal(Ok(Todo(2_147_483_648, "new", 0, 3, None, Pending)))
}

pub fn an_add_load_failure_is_reported_test() {
  let store =
    Store(fn() { Error("corrupt") }, fn(_) { Error("save must not run") })

  service.add(store, AddRequest("x", "0m", "3", None))
  |> should.equal(Error(service.Persisted("corrupt")))
}

pub fn an_add_save_failure_is_reported_test() {
  let store = Store(fn() { Ok([]) }, fn(_) { Error("disk") })

  service.add(store, AddRequest("x", "0m", "3", None))
  |> should.equal(Error(service.Persisted("disk")))
}

pub fn done_requires_a_numeric_id_test() {
  let task = Todo(10, "ten", 0, 3, None, Pending)

  service.done(store_with([task]), DoneRequest("ten"))
  |> should.equal(Error(service.Domain(InvalidInput)))
}

pub fn done_does_not_match_an_id_prefix_test() {
  let ten = Todo(10, "ten", 0, 3, None, Pending)
  let hundred = Todo(100, "one hundred", 0, 3, None, Pending)

  service.done(store_with([ten, hundred]), DoneRequest("1"))
  |> should.equal(Error(service.Domain(NotFound)))
}

pub fn done_saves_and_returns_the_completed_task_test() {
  let ten = Todo(10, "ten", 0, 3, None, Pending)
  let hundred = Todo(100, "one hundred", 0, 3, None, Pending)
  let store =
    Store(fn() { Ok([ten, hundred]) }, fn(tasks) {
      tasks |> should.equal([Todo(10, "ten", 0, 3, None, Done), hundred])
      Ok(Nil)
    })

  service.done(store, DoneRequest("10"))
  |> should.equal(Ok(Todo(10, "ten", 0, 3, None, Done)))
}

pub fn list_returns_pending_tasks_without_saving_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending)
  let completed = Todo(2, "y", 0, 3, None, Done)
  let store =
    Store(fn() { Ok([pending, completed]) }, fn(_) {
      Error("save must not run")
    })

  service.list(store, ListRequest(False)) |> should.equal(Ok([pending]))
}

pub fn a_missing_task_is_not_saved_test() {
  let task = Todo(1, "x", 0, 3, None, Pending)
  let store = Store(fn() { Ok([task]) }, fn(_) { Error("save must not run") })

  service.done(store, DoneRequest("99"))
  |> should.equal(Error(service.Domain(NotFound)))
}

pub fn an_already_completed_task_is_not_saved_test() {
  let completed = Todo(2, "y", 0, 3, None, Done)
  let store =
    Store(fn() { Ok([completed]) }, fn(_) { Error("save must not run") })

  service.done(store, DoneRequest("2"))
  |> should.equal(Error(service.Domain(AlreadyDone)))
}

pub fn a_done_save_failure_is_reported_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending)
  let store = Store(fn() { Ok([pending]) }, fn(_) { Error("rename") })

  service.done(store, DoneRequest("1"))
  |> should.equal(Error(service.Persisted("rename")))
}
