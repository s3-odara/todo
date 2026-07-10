import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import tasks/domain/model.{
  type AddRequest, type DoneRequest, type ListRequest, type Todo, AddRequest,
  AlreadyDone, Done, DoneRequest, InvalidInput, ListRequest, NotFound, Pending,
}
import todo_app/service.{type ServiceError, Domain, Persisted}

pub type Command {
  Help
  Add(AddRequest)
  List(ListRequest)
  RunDone(DoneRequest)
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
    ["list"] -> Ok(List(ListRequest(False)))
    ["list", "--all"] -> Ok(List(ListRequest(True)))
    ["done", id] -> Ok(RunDone(DoneRequest(id)))
    ["add", title, ..flags] ->
      flags
      |> add_flags(AddOptions(None, None, None))
      |> result.map(fn(options) {
        let AddOptions(estimate, priority, due) = options
        Add(AddRequest(
          title,
          option.unwrap(estimate, or: "0m"),
          option.unwrap(priority, or: "3"),
          due,
        ))
      })
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

pub fn service_error(error: ServiceError) -> Outcome {
  case error {
    Persisted(message) -> Outcome(1, [], ["Error: " <> message])
    Domain(AlreadyDone) -> Outcome(2, [], ["Error: task is already completed"])
    Domain(NotFound) -> Outcome(2, [], ["Error: task not found"])
    Domain(InvalidInput) -> Outcome(2, [], ["Error: invalid input"])
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
  int.to_string(task.id)
  <> "\t"
  <> case task.status {
    Pending -> "pending"
    Done -> "done"
  }
  <> "\t"
  <> int.to_string(task.priority)
  <> "\t"
  <> int.to_string(task.estimate_minutes)
  <> "m\t"
  <> case task.due {
    None -> "-"
    Some(due) -> due.canonical
  }
  <> "\t"
  <> task.title
}
