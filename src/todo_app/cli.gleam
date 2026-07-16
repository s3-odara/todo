import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import tasks/domain/availability.{type Availability, type Mutation}
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
  AvailabilityList
  MutateAvailability(Mutation)
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

type AvailabilityOptions {
  AvailabilityOptions(
    days: Option(List(availability.Weekday)),
    date: Option(calendar.Date),
    from: Option(String),
    to: Option(String),
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
    ["add", "--help"]
    | ["list", "--help"]
    | ["done", "--help"]
    | ["availability", "--help"] -> Ok(Help)
    ["availability", "list"] -> Ok(AvailabilityList)
    ["availability", action, ..flags] ->
      flags
      |> availability_flags(AvailabilityOptions(None, None, None, None))
      |> result.try(fn(options) { availability_command(action, options) })
      |> result.map(MutateAvailability)
      |> result.map_error(fn(_) { "invalid input" })
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

fn availability_flags(flags, options: AvailabilityOptions) {
  case flags, options {
    [], _ -> Ok(options)
    ["--day", value, ..rest], AvailabilityOptions(days: None, ..) -> {
      use days <- result.try(availability.parse_days(value))
      availability_flags(rest, AvailabilityOptions(..options, days: Some(days)))
    }
    ["--date", value, ..rest], AvailabilityOptions(date: None, ..) -> {
      use date <- result.try(availability.parse_date(value))
      availability_flags(rest, AvailabilityOptions(..options, date: Some(date)))
    }
    ["--from", value, ..rest], AvailabilityOptions(from: None, ..) ->
      availability_flags(
        rest,
        AvailabilityOptions(..options, from: Some(value)),
      )
    ["--to", value, ..rest], AvailabilityOptions(to: None, ..) ->
      availability_flags(rest, AvailabilityOptions(..options, to: Some(value)))
    _, _ -> Error(Nil)
  }
}

fn availability_command(action, options) -> Result(Mutation, Nil) {
  let AvailabilityOptions(days, date, from, to) = options
  case action, days, date, from, to {
    "add", Some(days), None, Some(from), Some(to) -> {
      use interval <- result.try(availability.parse_interval(from, to))
      Ok(availability.AddWeekly(days, interval))
    }
    "delete", Some(days), None, Some(from), Some(to) -> {
      use interval <- result.try(availability.parse_interval(from, to))
      Ok(availability.DeleteWeekly(days, interval))
    }
    "add", None, Some(date), Some(from), Some(to) -> {
      use interval <- result.try(availability.parse_interval(from, to))
      Ok(availability.AddDate(date, interval))
    }
    "delete", None, Some(date), Some(from), Some(to) -> {
      use interval <- result.try(availability.parse_interval(from, to))
      Ok(availability.DeleteDate(date, interval))
    }
    "set", None, Some(date), Some(from), Some(to) -> {
      use interval <- result.try(availability.parse_interval(from, to))
      Ok(availability.SetDate(date, interval))
    }
    "close", None, Some(date), None, None -> Ok(availability.CloseDate(date))
    "reset", None, Some(date), None, None -> Ok(availability.ResetDate(date))
    _, _, _, _, _ -> Error(Nil)
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
      "todo availability add|delete (--day DAY[,DAY...] | --date YYYY-MM-DD) --from HH:MM --to HH:MM",
      "todo availability set --date YYYY-MM-DD --from HH:MM --to HH:MM",
      "todo availability close|reset --date YYYY-MM-DD",
      "todo availability list",
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

pub fn availability_listed(value: Availability) -> Outcome {
  let availability.Availability(weekly, overrides) = value
  case weekly, overrides {
    [], [] -> Outcome(0, ["No availability configured."], [])
    _, _ -> {
      let weekly_lines =
        list.flat_map(weekly, fn(entry) {
          list.map(entry.intervals, fn(interval) {
            [
              "weekly",
              availability.weekday_string(entry.day),
              minute_text(interval.from),
              minute_text(interval.to),
            ]
            |> string.join("\t")
          })
        })
      let override_lines =
        list.flat_map(overrides, fn(entry) {
          let date = date_text(entry.date)
          case entry.intervals {
            [] -> ["override\t" <> date <> "\tclosed"]
            intervals ->
              list.map(intervals, fn(interval) {
                [
                  "override",
                  date,
                  minute_text(interval.from),
                  minute_text(interval.to),
                ]
                |> string.join("\t")
              })
          }
        })
      Outcome(0, list.append(weekly_lines, override_lines), [])
    }
  }
}

pub fn availability_updated() -> Outcome {
  Outcome(0, ["Availability updated."], [])
}

fn minute_text(value: Int) -> String {
  let hour = value / 60 |> int.to_string |> string.pad_start(2, "0")
  let minute = value % 60 |> int.to_string |> string.pad_start(2, "0")
  hour <> ":" <> minute
}

fn date_text(date: calendar.Date) -> String {
  [
    date.year |> int.to_string |> string.pad_start(4, "0"),
    date.month
      |> calendar.month_to_int
      |> int.to_string
      |> string.pad_start(2, "0"),
    date.day |> int.to_string |> string.pad_start(2, "0"),
  ]
  |> string.join("-")
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
