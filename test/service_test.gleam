import gleam/option.{None}
import gleeunit/should
import tasks/domain/model.{
  AddRequest, AlreadyDone, Done, DoneRequest, InvalidInput, ListRequest,
  NotFound, Pending, Todo,
}
import todo_app/service
import todo_app/store.{Store}

pub fn invalid_add_and_done_do_not_need_store_test() {
  let store =
    Store(fn() { Error("load must not run") }, fn(_) {
      Error("save must not run")
    })
  service.add(store, AddRequest("bad\n", "0m", "3", None))
  |> should.equal(Error(service.Domain(InvalidInput)))
  service.done(store, DoneRequest("01"))
  |> should.equal(Error(service.Domain(InvalidInput)))
}

pub fn add_defaults_max_plus_one_and_failures_test() {
  let items = [Todo(2_147_483_647, "old", 0, 3, None, Done)]
  let store = Store(fn() { Ok(items) }, fn(_) { Ok(Nil) })
  service.add(store, AddRequest("new", "0m", "3", None))
  |> should.equal(Ok(Todo(2_147_483_648, "new", 0, 3, None, Pending)))
  let load_failure =
    Store(fn() { Error("corrupt") }, fn(_) { Error("save must not run") })
  service.add(load_failure, AddRequest("x", "0m", "3", None))
  |> should.equal(Error(service.Persisted("corrupt")))
  let save_failure = Store(fn() { Ok([]) }, fn(_) { Error("disk") })
  service.add(save_failure, AddRequest("x", "0m", "3", None))
  |> should.equal(Error(service.Persisted("disk")))
}

pub fn done_rejects_title_and_does_not_prefix_match_ids_test() {
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
  let exact_store =
    Store(fn() { Ok([id_ten, id_one_hundred]) }, fn(items) {
      items |> should.equal([Todo(10, "ten", 0, 3, None, Done), id_one_hundred])
      Ok(Nil)
    })
  service.done(exact_store, DoneRequest("10"))
  |> should.equal(Ok(Todo(10, "ten", 0, 3, None, Done)))
}

pub fn list_done_and_no_save_cases_test() {
  let pending = Todo(1, "x", 0, 3, None, Pending)
  let done = Todo(2, "y", 0, 3, None, Done)
  let no_save =
    Store(fn() { Ok([pending, done]) }, fn(_) { Error("save must not run") })
  let assert Ok(items) = service.list(no_save, ListRequest(False))
  items |> should.equal([pending])
  service.done(no_save, DoneRequest("99"))
  |> should.equal(Error(service.Domain(NotFound)))
  service.done(no_save, DoneRequest("2"))
  |> should.equal(Error(service.Domain(AlreadyDone)))
  let save_failure = Store(fn() { Ok([pending]) }, fn(_) { Error("rename") })
  service.done(save_failure, DoneRequest("1"))
  |> should.equal(Error(service.Persisted("rename")))
}
