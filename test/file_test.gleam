import gleam/option.{None}
import gleeunit/should
import simplifile
import tasks/domain/model.{Pending, Todo}
import tasks/store/file

const root = "/tmp/todo-app-file-test"

pub fn missing_file_is_empty_test() {
  let _ = simplifile.delete_all([root])
  file.load(root <> "/missing.json") |> should.equal(Ok([]))
}

pub fn save_creates_parent_and_round_trips_test() {
  let _ = simplifile.delete_all([root])
  let path = root <> "/nested/tasks.json"
  let tasks = [Todo(1, "write report", 30, 3, None, Pending)]

  file.save(path, tasks) |> should.equal(Ok(Nil))
  file.load(path) |> should.equal(Ok(tasks))
  simplifile.read(path <> ".tmp") |> should.equal(Error(simplifile.Enoent))

  let _ = simplifile.delete_all([root])
}
