import gleam/option.{None}
import gleam/string
import gleeunit/should
import simplifile
import tasks/domain/app_state.{AppState}
import tasks/domain/availability
import tasks/domain/model.{Pending, Todo}
import tasks/domain/policy.{Spread}
import tasks/store/file
import test_support.{id}

const root = "/tmp/todo-app-file-test"

pub fn missing_file_is_an_empty_state_test() {
  let _ = simplifile.delete_all([root])
  file.load(root <> "/missing.json")
  |> should.equal(Ok(AppState([], availability.empty(), None)))
}

pub fn save_creates_parent_and_round_trips_state_test() {
  let _ = simplifile.delete_all([root])
  let path = root <> "/nested/tasks.json"
  let state =
    AppState(
      [Todo(id(1), "write report", 30, 3, None, Pending, Spread, 30)],
      availability.empty(),
      None,
    )

  file.save(path, state) |> should.equal(Ok(Nil))
  file.load(path) |> should.equal(Ok(state))
  simplifile.read(path <> ".tmp") |> should.equal(Error(simplifile.Enoent))
  let assert Ok(saved) = simplifile.read(path)
  string.starts_with(saved, "{\"tasks\":") |> should.be_true

  let _ = simplifile.delete_all([root])
}
