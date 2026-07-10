import gleam/option.{None, Some}
import gleeunit/should
import tasks/domain/model.{AddRequest, DoneRequest, ListRequest, Pending, Todo}
import todo_app/cli
import todo_app/runtime
import todo_app/store.{Store}

fn run(args, store) {
  case cli.parse(args) {
    Ok(command) -> runtime.run(command, store)
    Error(message) -> cli.grammar_error(message)
  }
}

pub fn grammar_matrix_test() {
  cli.parse(["add", "x", "--estimate", "0m", "--estimate", "1h"])
  |> should.equal(Error("invalid, duplicate, or missing option"))
  cli.parse(["add", "x", "--priority", "3", "--priority", "4"])
  |> should.equal(Error("invalid, duplicate, or missing option"))
  cli.parse(["add", "x", "--due", "2026-01-01", "--due", "2026-01-02"])
  |> should.equal(Error("invalid, duplicate, or missing option"))
  cli.parse(["list", "--help", "extra"])
  |> should.equal(Error("invalid command or arguments"))
  cli.parse(["add", "x", "--unknown", "y"])
  |> should.equal(Error("invalid, duplicate, or missing option"))
  cli.parse(["add", "x", "--estimate"])
  |> should.equal(Error("invalid, duplicate, or missing option"))
  cli.parse([
    "add",
    "x",
    "--due",
    "2026-01-01",
    "--priority",
    "5",
    "--estimate",
    "2h",
  ])
  |> should.equal(Ok(cli.Add(AddRequest("x", "2h", "5", Some("2026-01-01")))))
  cli.parse(["done"]) |> should.equal(Error("invalid command or arguments"))
  cli.parse(["done", "1", "extra"])
  |> should.equal(Error("invalid command or arguments"))
  cli.parse(["list", "--all", "extra"])
  |> should.equal(Error("invalid command or arguments"))
  cli.parse(["add", "--help"]) |> should.equal(Ok(cli.Help))
  cli.parse(["list", "--all"]) |> should.equal(Ok(cli.List(ListRequest(True))))
}

pub fn exact_outcome_and_rendering_matrix_test() {
  let empty = Store(fn() { Ok([]) }, fn(_) { Ok(Nil) })
  run([], empty) |> should.equal(cli.help())
  run(["wat"], empty)
  |> should.equal(cli.Outcome(2, [], ["Error: invalid command or arguments"]))
  run(["add", "x", "--priority", "9"], empty)
  |> should.equal(cli.Outcome(2, [], ["Error: invalid input"]))
  run(["list"], empty)
  |> should.equal(cli.Outcome(0, ["No pending tasks."], []))
  run(["list", "--all"], empty)
  |> should.equal(cli.Outcome(0, ["No tasks."], []))
  let one =
    Store(fn() { Ok([Todo(1, "x", 5, 3, None, Pending)]) }, fn(_) { Ok(Nil) })
  run(["list"], one)
  |> should.equal(
    cli.Outcome(
      0,
      ["ID\tSTATUS\tPRIORITY\tESTIMATE\tDUE\tTITLE", "1\tpending\t3\t5m\t-\tx"],
      [],
    ),
  )
  run(["done", "99"], one)
  |> should.equal(cli.Outcome(2, [], ["Error: task not found"]))
}

pub fn success_defaults_and_done_outcomes_test() {
  let add_store = Store(fn() { Ok([]) }, fn(_) { Ok(Nil) })
  run(["add", "x"], add_store)
  |> should.equal(cli.Outcome(0, ["Added task 1: x"], []))
  let done_store =
    Store(fn() { Ok([Todo(1, "x", 0, 3, None, Pending)]) }, fn(_) { Ok(Nil) })
  run(["done", "1"], done_store)
  |> should.equal(cli.Outcome(0, ["Completed task 1: x"], []))
  cli.parse(["add", "x"])
  |> should.equal(Ok(cli.Add(AddRequest("x", "0m", "3", None))))
  cli.parse(["done", "1"]) |> should.equal(Ok(cli.RunDone(DoneRequest("1"))))
}
