import gleam/option.{None}
import gleeunit/should
import tasks/domain/model.{
  AddRequest, AlreadyDone, Done, DoneRequest, InvalidInput, ListRequest,
  NotFound, Pending, Todo,
}
import todo_app/service
import todo_app/store.{Store}

pub fn invalid_requests_do_not_load_the_store_test() {
  let store =
    Store(fn() { Error("load must not run") }, fn(_) {
      Error("save must not run")
    })
  service.add(store, AddRequest("bad\n", "0m", "3", None))
  |> should.equal(Error(service.Domain(InvalidInput)))
  service.done(store, DoneRequest("01"))
  |> should.equal(Error(service.Domain(InvalidInput)))
}

pub fn add_uses_the_next_id_test() {
  let items = [Todo(2_147_483_647, "old", 0, 3, None, Done)]
  let store = Store(fn() { Ok(items) }, fn(_) { Ok(Nil) })
  service.add(store, AddRequest("new", "0m", "3", None))
  |> should.equal(Ok(Todo(2_147_483_648, "new", 0, 3, None, Pending)))
}

pub fn add_reports_load_and_save_failures_test() {
  let load_failure =
    Store(fn() { Error("corrupt") }, fn(_) { Error("save must not run") })
  service.add(load_failure, AddRequest("x", "0m", "3", None))
  |> should.equal(Error(service.Persisted("corrupt")))

  let save_failure = Store(fn() { Ok([]) }, fn(_) { Error("disk") })
  service.add(save_failure, AddRequest("x", "0m", "3", None))
  |> should.equal(Error(service.Persisted("disk")))
}

pub fn done_requires_an_exact_numeric_id_test() {
  let id_ten = Todo(10, "ten", 0, 3, None, Pending)
  let id_one_hundred = Todo(100, "one hundred", 0, 3, None, Pending)
  let store =
    Store(fn() { Ok([id_ten, id_one_hundred]) }, fn(_) {
      Error("save must not run")
    })
  service.done(store, DoneRequest("ten"))
  |> should.equal(Error(service.Domain(InvalidInput)))
  service.done(store, DoneRequest("1"))
  |> should.equal(Error(service.Domain(NotFound)))
}

pub fn done_saves_the_completed_task_test() {
  let id_ten = Todo(10, "ten", 0, 3, None, Pending)
  let id_one_hundred = Todo(100, "one hundred", 0, 3, None, Pending)
  let store =
    Store(fn() { Ok([id_ten, id_one_hundred]) }, fn(items) {
      items |> should.equal([Todo(10, "ten", 0, 3, None, Done), id_one_hundred])
      Ok(Nil)
    })
  service.done(store, DoneRequest("10"))
  |> should.equal(Ok(Todo(10, "ten", 0, 3, None, Done)))
}

pub fn list_filters_without_saving_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending)
  let done = Todo(2, "y", 0, 3, None, Done)
  let store =
    Store(fn() { Ok([pending, done]) }, fn(_) { Error("save must not run") })
  service.list(store, ListRequest(False)) |> should.equal(Ok([pending]))
}

pub fn done_does_not_save_missing_or_completed_tasks_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending)
  let done = Todo(2, "y", 0, 3, None, Done)
  let store =
    Store(fn() { Ok([pending, done]) }, fn(_) { Error("save must not run") })
  service.done(store, DoneRequest("99"))
  |> should.equal(Error(service.Domain(NotFound)))
  service.done(store, DoneRequest("2"))
  |> should.equal(Error(service.Domain(AlreadyDone)))
}

pub fn done_reports_save_failure_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending)
  let store = Store(fn() { Ok([pending]) }, fn(_) { Error("rename") })
  service.done(store, DoneRequest("1"))
  |> should.equal(Error(service.Persisted("rename")))
}
