import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt}
import gleam/result
import gleam/string
import gleam/time/calendar
import tasks/domain/due
import tasks/domain/filter.{
  type DueFilter, type ListFilter, type StatusFilter, AllStatuses, DoneOnly,
  Exact, ListFilter, Overdue, PendingOnly, Range, Today,
}
import tasks/domain/model.{
  type Due, type Status, type TaskError, type Todo, type ValidatedAdd,
  AlreadyDone, Done, NotFound, Pending,
}
import tasks/domain/validation

pub type Command {
  Help
  Add(ValidatedAdd)
  List(ListFilter)
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

type ListOptions {
  ListOptions(
    done: Bool,
    all: Bool,
    due: Option(DueFilter),
    since: Option(calendar.Date),
    until: Option(calendar.Date),
  )
}

pub fn parse(args: List(String)) -> Result(Command, String) {
  case args {
    [] | ["--help"] -> Ok(Help)
    ["add", "--help"] | ["list", "--help"] | ["done", "--help"] -> Ok(Help)
    ["list", ..flags] ->
      flags
      |> list_flags(ListOptions(False, False, None, None, None))
      |> result.try(list_filter)
      |> result.map(List)
      |> result.map_error(fn(_) { "invalid input" })
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

fn list_flags(flags, options: ListOptions) -> Result(ListOptions, Nil) {
  case flags, options {
    [], _ -> Ok(options)
    ["--done", ..rest], ListOptions(done: False, ..) ->
      list_flags(rest, ListOptions(..options, done: True))
    ["--all", ..rest], ListOptions(all: False, ..) ->
      list_flags(rest, ListOptions(..options, all: True))
    ["--due", value, ..rest], ListOptions(due: None, ..) -> {
      use parsed <- result.try(parse_due_filter(value))
      list_flags(rest, ListOptions(..options, due: Some(parsed)))
    }
    ["--due-since", value, ..rest], ListOptions(since: None, ..) -> {
      use parsed <- result.try(due.parse_date(value))
      list_flags(rest, ListOptions(..options, since: Some(parsed)))
    }
    ["--due-until", value, ..rest], ListOptions(until: None, ..) -> {
      use parsed <- result.try(due.parse_date(value))
      list_flags(rest, ListOptions(..options, until: Some(parsed)))
    }
    _, _ -> Error(Nil)
  }
}

fn parse_due_filter(value: String) -> Result(DueFilter, Nil) {
  case value {
    "today" -> Ok(Today)
    "overdue" -> Ok(Overdue)
    value -> due.parse_date(value) |> result.map(Exact)
  }
}

fn list_filter(options: ListOptions) -> Result(ListFilter, Nil) {
  let ListOptions(done, all, exact, since, until) = options
  case done && all, exact, since, until {
    True, _, _, _ -> Error(Nil)
    False, Some(_), Some(_), _ | False, Some(_), _, Some(_) -> Error(Nil)
    False, _, Some(start), Some(end) ->
      case calendar.naive_date_compare(start, end) {
        Gt -> Error(Nil)
        _ -> Ok(ListFilter(status_filter(done, all), Some(Range(since, until))))
      }
    False, _, _, _ -> {
      let status = status_filter(done, all)
      let due_filter = case exact, since, until {
        Some(filter), _, _ -> Some(filter)
        None, None, None -> None
        None, _, _ -> Some(Range(since, until))
      }
      Ok(ListFilter(status, due_filter))
    }
  }
}

fn status_filter(done: Bool, all: Bool) -> StatusFilter {
  case done, all {
    True, _ -> DoneOnly
    _, True -> AllStatuses
    _, _ -> PendingOnly
  }
}

pub fn help() -> Outcome {
  Outcome(
    0,
    [
      "todo add TITLE [--estimate DURATION] [--priority PRIORITY] [--due DUE]",
      "todo list [--done | --all] [--due today|overdue|YYYY-MM-DD]",
      "          [--due-since YYYY-MM-DD] [--due-until YYYY-MM-DD]",
      "  default: pending; --done: done; --all: both",
      "  due dates use local today; overdue is before today; ranges are inclusive",
      "  --due excludes undated tasks and cannot be combined with due ranges",
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

pub fn domain_error(error: TaskError) -> Outcome {
  case error {
    AlreadyDone -> grammar_error("task is already completed")
    NotFound -> grammar_error("task not found")
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

pub fn listed(items: List(Todo), status: StatusFilter) -> Outcome {
  case items {
    [] ->
      Outcome(
        0,
        [
          case status {
            PendingOnly -> "No pending tasks."
            DoneOnly -> "No done tasks."
            AllStatuses -> "No tasks."
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
