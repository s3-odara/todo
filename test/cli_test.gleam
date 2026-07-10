import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import tasks/domain/model.{AddRequest, Done, DoneRequest, Pending, Todo}
import todo_app/cli
import todo_app/runtime
import todo_app/store.{Store}

fn run(args, store) {
  case cli.parse(args) {
    Ok(command) -> runtime.run(command, store)
    Error(message) -> cli.grammar_error(message)
  }
}

fn store_with(tasks) {
  Store(fn() { Ok(tasks) }, fn(_) { Ok(Nil) })
}

pub fn help_is_selected_when_no_command_or_a_help_flag_is_given_test() {
  [[], ["--help"], ["add", "--help"], ["list", "--help"], ["done", "--help"]]
  |> list.each(fn(args) { cli.parse(args) |> should.equal(Ok(cli.Help)) })
}

pub fn help_lists_the_available_commands_test() {
  cli.help()
  |> should.equal(
    cli.Outcome(
      0,
      [
        "todo add TITLE [--estimate DURATION] [--priority PRIORITY] [--due DUE]",
        "todo list [--all]",
        "todo done ID",
      ],
      [],
    ),
  )
}

pub fn add_uses_default_estimate_and_priority_test() {
  cli.parse(["add", "x"])
  |> should.equal(Ok(cli.Add(AddRequest("x", "0m", "3", None))))
}

pub fn add_options_can_be_given_in_any_order_test() {
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
}

pub fn duplicate_add_options_are_rejected_test() {
  [
    ["add", "x", "--estimate", "0m", "--estimate", "1h"],
    ["add", "x", "--priority", "3", "--priority", "4"],
    ["add", "x", "--due", "2026-01-01", "--due", "2026-01-02"],
  ]
  |> list.each(fn(args) {
    cli.parse(args)
    |> should.equal(Error("invalid, duplicate, or missing option"))
  })
}

pub fn unknown_or_incomplete_add_options_are_rejected_test() {
  [["add", "x", "--unknown", "y"], ["add", "x", "--estimate"]]
  |> list.each(fn(args) {
    cli.parse(args)
    |> should.equal(Error("invalid, duplicate, or missing option"))
  })
}

pub fn invalid_command_shapes_are_rejected_test() {
  [
    ["wat"],
    ["done"],
    ["done", "1", "extra"],
    ["list", "--all", "extra"],
    ["list", "--help", "extra"],
  ]
  |> list.each(fn(args) {
    cli.parse(args) |> should.equal(Error("invalid command or arguments"))
  })
}

pub fn done_parses_its_id_test() {
  cli.parse(["done", "1"])
  |> should.equal(Ok(cli.RunDone(DoneRequest("1"))))
}

pub fn an_empty_list_reports_whether_completed_tasks_were_requested_test() {
  let empty = store_with([])

  run(["list"], empty)
  |> should.equal(cli.Outcome(0, ["No pending tasks."], []))
  run(["list", "--all"], empty)
  |> should.equal(cli.Outcome(0, ["No tasks."], []))
}

pub fn tasks_are_rendered_as_tab_separated_rows_test() {
  let store = store_with([Todo(1, "x", 5, 3, None, Pending)])

  run(["list"], store)
  |> should.equal(
    cli.Outcome(
      0,
      ["ID\tSTATUS\tPRIORITY\tESTIMATE\tDUE\tTITLE", "1\tpending\t3\t5m\t-\tx"],
      [],
    ),
  )
}

pub fn invalid_input_is_reported_on_stderr_test() {
  run(["add", "x", "--priority", "9"], store_with([]))
  |> should.equal(cli.Outcome(2, [], ["Error: invalid input"]))
}

pub fn an_unknown_task_is_reported_on_stderr_test() {
  let store = store_with([Todo(1, "x", 5, 3, None, Pending)])

  run(["done", "99"], store)
  |> should.equal(cli.Outcome(2, [], ["Error: task not found"]))
}

pub fn an_already_completed_task_is_reported_on_stderr_test() {
  let store = store_with([Todo(1, "x", 5, 3, None, Done)])

  run(["done", "1"], store)
  |> should.equal(cli.Outcome(2, [], ["Error: task is already completed"]))
}

pub fn a_persistence_failure_is_reported_with_exit_code_one_test() {
  let store = Store(fn() { Error("corrupt data") }, fn(_) { Ok(Nil) })

  run(["list"], store)
  |> should.equal(cli.Outcome(1, [], ["Error: corrupt data"]))
}

pub fn adding_a_task_reports_its_id_and_title_test() {
  run(["add", "x"], store_with([]))
  |> should.equal(cli.Outcome(0, ["Added task 1: x"], []))
}

pub fn completing_a_task_reports_its_id_and_title_test() {
  let store = store_with([Todo(1, "x", 0, 3, None, Pending)])

  run(["done", "1"], store)
  |> should.equal(cli.Outcome(0, ["Completed task 1: x"], []))
}
