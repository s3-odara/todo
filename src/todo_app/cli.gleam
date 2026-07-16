import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import tasks/domain/due.{type Due}
import tasks/domain/filter.{
  type DueFilter, type ListFilter, type StatusFilter, AllStatuses, DoneOnly,
  Exact, ListFilter, Overdue, PendingOnly, Range, Today,
}
import tasks/domain/model.{
  type Status, type TaskError, type Todo, type ValidatedAdd, AlreadyDone, Done,
  NotFound, Pending,
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
    scheduling_policy: Option(String),
    minimum_split: Option(String),
  )
}

type ListOptions {
  ListOptions(status: Option(StatusFilter), due: ListDueOptions)
}

type ListDueOptions {
  NoDueOptions
  DueMatch(DueFilter)
  DueRange(since: Option(calendar.Date), until: Option(calendar.Date))
}

pub fn parse(
  args: List(String),
  due_parser: fn(String) -> Result(Due, Nil),
) -> Result(Command, String) {
  case args {
    [] | ["--help"] -> Ok(Help)
    ["add", "--help"] | ["list", "--help"] | ["done", "--help"] -> Ok(Help)
    ["list", ..flags] ->
      flags
      |> list_flags(ListOptions(None, NoDueOptions))
      |> result.try(list_filter)
      |> result.map(List)
      |> result.map_error(fn(_) { "invalid input" })
    ["done", id] ->
      validation.done(id)
      |> result.map(RunDone)
      |> result.map_error(fn(_) { "invalid input" })
    ["add", title, ..flags] ->
      flags
      |> add_flags(AddOptions(None, None, None, None, None))
      |> result.try(fn(options) {
        let AddOptions(estimate, priority, due, policy, minimum_split) = options
        validation.add(
          title,
          option.unwrap(estimate, or: "0m"),
          option.unwrap(priority, or: "3"),
          due,
          option.unwrap(policy, or: "spread"),
          option.unwrap(minimum_split, or: "30m"),
          due_parser,
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
    ["--scheduling-policy", value, ..rest],
      AddOptions(scheduling_policy: None, ..)
    -> add_flags(rest, AddOptions(..options, scheduling_policy: Some(value)))
    ["--minimum-split", value, ..rest], AddOptions(minimum_split: None, ..) ->
      add_flags(rest, AddOptions(..options, minimum_split: Some(value)))
    _, _ -> Error("invalid, duplicate, or missing option")
  }
}

fn list_flags(flags, options: ListOptions) -> Result(ListOptions, Nil) {
  case flags {
    [] -> Ok(options)
    ["--done", ..rest] -> {
      use updated <- result.try(select_status(options, DoneOnly))
      list_flags(rest, updated)
    }
    ["--all", ..rest] -> {
      use updated <- result.try(select_status(options, AllStatuses))
      list_flags(rest, updated)
    }
    ["--due", value, ..rest] -> {
      use parsed <- result.try(parse_due_filter(value))
      use updated <- result.try(select_due(options, parsed))
      list_flags(rest, updated)
    }
    ["--due-since", value, ..rest] -> {
      use parsed <- result.try(due.parse_date(value))
      use updated <- result.try(set_since(options, parsed))
      list_flags(rest, updated)
    }
    ["--due-until", value, ..rest] -> {
      use parsed <- result.try(due.parse_date(value))
      use updated <- result.try(set_until(options, parsed))
      list_flags(rest, updated)
    }
    _ -> Error(Nil)
  }
}

fn select_status(
  options: ListOptions,
  status: StatusFilter,
) -> Result(ListOptions, Nil) {
  case options {
    ListOptions(status: None, ..) ->
      Ok(ListOptions(..options, status: Some(status)))
    _ -> Error(Nil)
  }
}

fn select_due(
  options: ListOptions,
  filter: DueFilter,
) -> Result(ListOptions, Nil) {
  case options {
    ListOptions(due: NoDueOptions, ..) ->
      Ok(ListOptions(..options, due: DueMatch(filter)))
    _ -> Error(Nil)
  }
}

fn set_since(
  options: ListOptions,
  since: calendar.Date,
) -> Result(ListOptions, Nil) {
  case options {
    ListOptions(due: NoDueOptions, ..) ->
      Ok(ListOptions(..options, due: DueRange(Some(since), None)))
    ListOptions(due: DueRange(since: None, until: until), ..) ->
      Ok(ListOptions(..options, due: DueRange(Some(since), until)))
    _ -> Error(Nil)
  }
}

fn set_until(
  options: ListOptions,
  until: calendar.Date,
) -> Result(ListOptions, Nil) {
  case options {
    ListOptions(due: NoDueOptions, ..) ->
      Ok(ListOptions(..options, due: DueRange(None, Some(until))))
    ListOptions(due: DueRange(since: since, until: None), ..) ->
      Ok(ListOptions(..options, due: DueRange(since, Some(until))))
    _ -> Error(Nil)
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
  let ListOptions(status, due_options) = options
  let status = option.unwrap(status, or: PendingOnly)
  case due_options {
    NoDueOptions -> Ok(ListFilter(status, None))
    DueMatch(filter) -> Ok(ListFilter(status, Some(filter)))
    DueRange(Some(start), Some(end)) ->
      case calendar.naive_date_compare(start, end) {
        Gt -> Error(Nil)
        _ -> Ok(ListFilter(status, Some(Range(Some(start), Some(end)))))
      }
    DueRange(since, until) -> Ok(ListFilter(status, Some(Range(since, until))))
  }
}

pub fn help() -> Outcome {
  Outcome(
    0,
    [
      "todo add TITLE [--estimate DURATION] [--priority PRIORITY] [--due DUE]",
      "               [--scheduling-policy asap|spread|near_deadline]",
      "               [--minimum-split DURATION]",
      "todo list [--done | --all] [--due today|overdue|YYYY-MM-DD]",
      "          [--due-since YYYY-MM-DD] [--due-until YYYY-MM-DD]",
      "  default: pending; --done: done; --all: both",
      "  due dates use local time; overdue is before now; ranges are inclusive",
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

pub fn listed(
  items: List(Todo),
  status: StatusFilter,
  offset: Duration,
) -> Outcome {
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
          ..list.map(items, fn(task) { task_line(task, offset) })
        ],
        [],
      )
  }
}

fn task_line(task: Todo, offset: Duration) -> String {
  [
    int.to_string(task.id),
    status_text(task.status),
    int.to_string(task.priority),
    int.to_string(task.estimate_minutes) <> "m",
    due_text(task.due, offset),
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

fn due_text(due_value: Option(Due), offset: Duration) -> String {
  case due_value {
    None -> "-"
    Some(value) -> due.format(value, offset)
  }
}
