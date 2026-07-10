import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import tasks/domain/model.{
  type AddRequest, type DoneRequest, type ListRequest, type Todo, AddRequest,
  AlreadyDone, Done, DoneRequest, ListRequest, NotFound, Pending,
}
import todo_app/service.{type ServiceError, Input, Persisted}

pub type Command {
  Help
  Add(AddRequest)
  List(ListRequest)
  RunDone(DoneRequest)
}

pub type Outcome {
  Outcome(code: Int, stdout_lines: List(String), stderr_lines: List(String))
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
      |> add_flags("0m", "3", None, False, False, False)
      |> result.map(fn(values) {
        let #(estimate, priority, due) = values
        Add(AddRequest(title, estimate, priority, due))
      })
    _ -> Error("invalid command or arguments")
  }
}

fn add_flags(
  flags,
  estimate,
  priority,
  due,
  estimate_seen,
  priority_seen,
  due_seen,
) -> Result(#(String, String, Option(String)), String) {
  case flags {
    [] -> Ok(#(estimate, priority, due))
    ["--estimate", value, ..rest] if !estimate_seen ->
      add_flags(rest, value, priority, due, True, priority_seen, due_seen)
    ["--priority", value, ..rest] if !priority_seen ->
      add_flags(rest, estimate, value, due, estimate_seen, True, due_seen)
    ["--due", value, ..rest] if !due_seen ->
      add_flags(
        rest,
        estimate,
        priority,
        Some(value),
        estimate_seen,
        priority_seen,
        True,
      )
    _ -> Error("invalid, duplicate, or missing option")
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

pub fn service_error(error: ServiceError) -> Outcome {
  case error {
    Persisted(message) -> Outcome(1, [], ["Error: " <> message])
    Input(AlreadyDone) -> Outcome(2, [], ["Error: task is already completed"])
    Input(NotFound) -> Outcome(2, [], ["Error: task not found"])
    Input(_) -> Outcome(2, [], ["Error: invalid input"])
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
