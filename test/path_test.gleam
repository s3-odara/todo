import gleam/option.{None, Some}
import gleeunit/should
import todo_app/store/path

pub fn todo_file_wins_test() {
  path.resolve(Some("relative.yaml"), Some("/xdg"), Some("/home/a"))
  |> should.equal(Ok("relative.yaml"))
}

pub fn xdg_fallback_test() {
  path.resolve(None, Some("/xdg"), Some("/home/a"))
  |> should.equal(Ok("/xdg/todo/tasks.yaml"))
}

pub fn home_fallback_test() {
  path.resolve(None, None, Some("/home/a"))
  |> should.equal(Ok("/home/a/.local/share/todo/tasks.yaml"))
}

pub fn missing_environment_test() {
  path.resolve(None, None, None)
  |> should.equal(Error("TODO_FILE, XDG_DATA_HOME, or HOME is required"))
}

pub fn empty_values_are_absent_test() {
  path.resolve(Some(""), Some(""), Some("/home/a"))
  |> should.equal(Ok("/home/a/.local/share/todo/tasks.yaml"))
}
