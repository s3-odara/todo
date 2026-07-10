import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tasks/domain/model.{
  type Due, type Error, type Status, type Todo, type ValidatedAdd, AlreadyDone,
  Done, InvalidInput, NotFound, Pending,
}
import tasks/domain/validation

pub type Command {
  Help
  Add(ValidatedAdd)
  List(include_all: Bool)
  RunDone(id: Int)
}

pub type Outcome {
  Outcome(code: Int, stdout_lines: List(String), stderr_lines: List(String))
}

type AddOptions {
  AddOptions(
    estimate: Option(String),
    priority: Option(String),
    due: Option(String),
  )
}

pub fn parse(args: List(String)) -> Result(Command, String) {
  case args {
    [] | ["--help"] -> Ok(Help)
    ["add", "--help"] | ["list", "--help"] | ["done", "--help"] -> Ok(Help)
    ["list"] -> Ok(List(False))
    ["list", "--all"] -> Ok(List(True))
    ["done", id] ->
      validation.done(id)
      |> result.map(RunDone)
      |> result.map_error(fn(_) { "invalid input" })
    ["add", title, ..flags] ->
      flags
      |> add_flags(AddOptions(None, None, None))
      |> result.try(fn(options) {
        let AddOptions(estimate, priority, due) = options
        validation.add(
          title,
          option.unwrap(estimate, or: "0m"),
          option.unwrap(priority, or: "3"),
          due,
        )
        |> result.map_error(fn(_) { "invalid input" })
      })
      |> result.map(Add)
    _ -> Error("invalid command or arguments")
  }
}

fn add_flags(flags, options: AddOptions) -> Result(AddOptions, String) {
  case flags, options {
    [], _ -> Ok(options)
    ["--estimate", value, ..rest], AddOptions(estimate: None, ..) ->
      add_flags(rest, AddOptions(..options, estimate: Some(value)))
    ["--priority", value, ..rest], AddOptions(priority: None, ..) ->
      add_flags(rest, AddOptions(..options, priority: Some(value)))
    ["--due", value, ..rest], AddOptions(due: None, ..) ->
      add_flags(rest, AddOptions(..options, due: Some(value)))
    _, _ -> Error("invalid, duplicate, or missing option")
  }
}

pub fn help() -> Outcome {
  Outcome(
    0,
    [
      "todo add TITLE [--estimate DURATION] [--priority PRIORITY] [--due DUE]",
      "todo list [--all]",
      "todo done ID",
    ],
    [],
  )
}

pub fn grammar_error(message: String) -> Outcome {
  Outcome(2, [], ["Error: " <> message])
}

pub fn persistence_error(message: String) -> Outcome {
  Outcome(1, [], ["Error: " <> message])
}

pub fn domain_error(error: Error) -> Outcome {
  case error {
    AlreadyDone -> grammar_error("task is already completed")
    NotFound -> grammar_error("task not found")
    // Commands are validated before execution, so this cannot originate here.
    InvalidInput -> grammar_error("invalid input")
  }
}

pub fn added(task: Todo) -> Outcome {
  Outcome(
    0,
    ["Added task " <> int.to_string(task.id) <> ": " <> task.title],
    [],
  )
}

pub fn completed(task: Todo) -> Outcome {
  Outcome(
    0,
    ["Completed task " <> int.to_string(task.id) <> ": " <> task.title],
    [],
  )
}

pub fn listed(items: List(Todo), all: Bool) -> Outcome {
  case items {
    [] ->
      Outcome(
        0,
        [
          case all {
            True -> "No tasks."
            False -> "No pending tasks."
          },
        ],
        [],
      )
    _ ->
      Outcome(
        0,
        [
          "ID\tSTATUS\tPRIORITY\tESTIMATE\tDUE\tTITLE",
          ..list.map(items, task_line)
        ],
        [],
      )
  }
}

fn task_line(task: Todo) -> String {
  [
    int.to_string(task.id),
    status_text(task.status),
    int.to_string(task.priority),
    int.to_string(task.estimate_minutes) <> "m",
    due_text(task.due),
    task.title,
  ]
  |> string.join("\t")
}

fn status_text(status: Status) -> String {
  case status {
    Pending -> "pending"
    Done -> "done"
  }
}

fn due_text(due: Option(Due)) -> String {
  case due {
    None -> "-"
    Some(value) -> value.canonical
  }
}
