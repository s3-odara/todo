import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import gleam/time/timestamp
import tasks/domain/availability.{type Availability, type Mutation}
import tasks/domain/due.{type Due}
import tasks/domain/filter.{
  type StatusFilter, type TimeFilter, AllStatuses, AnyTime, DateRange, DoneOnly,
  On, Overdue, PendingOnly, Today,
}
import tasks/domain/local_time
import tasks/domain/model.{
  type AddValues, type TaskError, type Todo, AlreadyDone, AmbiguousId, NotFound,
  status_to_string,
}
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/scheduler.{type SchedulingError}
import tasks/domain/task_id.{type TaskId}
import tasks/domain/validation

pub type Command {
  Help
  Add(id: TaskId, values: AddValues)
  ListTasks(status: StatusFilter, filter: TimeFilter)
  ListScheduled(status: StatusFilter, filter: TimeFilter)
  GenerateSchedule
  RunDone(selector: String)
  AvailabilityList
  MutateAvailability(Mutation)
}

pub type Outcome {
  Outcome(code: Int, stdout_lines: List(String), stderr_lines: List(String))
}

pub fn parse(
  args: List(String),
  due_parser: fn(String) -> Result(Due, Nil),
) -> Result(Command, String) {
  parse_with_id(args, due_parser, task_id.generate)
}

/// ID generation is injected so parsing remains deterministic in tests while
/// production creates the UUID at the CLI boundary, outside the pure runtime.
pub fn parse_with_id(
  args: List(String),
  due_parser: fn(String) -> Result(Due, Nil),
  generate_id: fn() -> TaskId,
) -> Result(Command, String) {
  case args {
    []
    | ["--help"]
    | ["add", "--help"]
    | ["list", "--help"]
    | ["list", "scheduled", "--help"]
    | ["done", "--help"]
    | ["availability", "--help"]
    | ["availability", "list", "--help"]
    | ["availability", "weekly", "add", "--help"]
    | ["availability", "weekly", "delete", "--help"]
    | ["availability", "date", "add", "--help"]
    | ["availability", "date", "delete", "--help"]
    | ["availability", "date", "set", "--help"]
    | ["availability", "date", "close", "--help"]
    | ["availability", "date", "reset", "--help"]
    | ["schedule", "--help"] -> Ok(Help)
    ["schedule"] -> Ok(GenerateSchedule)
    ["done", id] ->
      validation.done(id)
      |> result.map(RunDone)
      |> result.map_error(fn(_) { "invalid input" })
    ["add", title, ..options] ->
      add_command(title, due_parser, generate_id, options)
    ["list", "scheduled", ..options] -> scheduled_list_command(options)
    ["list", ..options] -> task_list_command(options)
    ["availability", "list"] -> Ok(AvailabilityList)
    ["availability", "weekly", "add", ..options] ->
      weekly_command(options, availability.AddWeekly)
    ["availability", "weekly", "delete", ..options] ->
      weekly_command(options, availability.DeleteWeekly)
    ["availability", "date", "add", ..options] ->
      date_interval_command(options, availability.AddDate)
    ["availability", "date", "delete", ..options] ->
      date_interval_command(options, availability.DeleteDate)
    ["availability", "date", "set", ..options] ->
      date_interval_command(options, availability.SetDate)
    ["availability", "date", "close", ..options] ->
      date_command(options, availability.CloseDate)
    ["availability", "date", "reset", ..options] ->
      date_command(options, availability.ResetDate)
    _ -> Error("invalid command or arguments")
  }
}

type Options =
  List(#(String, String))

fn add_command(title, due_parser, generate_id, args) {
  use options <- result.try(
    parse_options(args, [
      "estimate",
      "priority",
      "due",
      "scheduling-policy",
      "minimum-split",
    ]),
  )
  validation.add(
    title,
    value_or(options, "estimate", "0m"),
    value_or(options, "priority", "3"),
    optional_value(options, "due"),
    value_or(options, "scheduling-policy", "spread"),
    value_or(options, "minimum-split", "30m"),
    due_parser,
  )
  |> result.map(fn(values) { Add(generate_id(), values) })
  |> invalid_input
}

fn task_list_command(args) {
  use options <- result.try(
    parse_options(args, [
      "status",
      "due",
      "due-since",
      "due-until",
    ]),
  )
  use status <- result.try(status_filter(options) |> invalid_input)
  use exact <- result.try(
    optional_parsed(options, "due", parse_due_filter) |> invalid_input,
  )
  use since <- result.try(
    optional_parsed(options, "due-since", due.parse_date) |> invalid_input,
  )
  use until <- result.try(
    optional_parsed(options, "due-until", due.parse_date) |> invalid_input,
  )
  temporal_filter(exact, since, until)
  |> result.map(fn(temporal) { ListTasks(status, temporal) })
  |> invalid_input
}

fn scheduled_list_command(args) {
  use options <- result.try(
    parse_options(args, [
      "status",
      "on",
      "since",
      "until",
    ]),
  )
  use status <- result.try(status_filter(options) |> invalid_input)
  use exact <- result.try(
    optional_parsed(options, "on", parse_scheduled_exact) |> invalid_input,
  )
  use since <- result.try(
    optional_parsed(options, "since", due.parse_date) |> invalid_input,
  )
  use until <- result.try(
    optional_parsed(options, "until", due.parse_date) |> invalid_input,
  )
  temporal_filter(exact, since, until)
  |> result.map(fn(temporal) { ListScheduled(status, temporal) })
  |> invalid_input
}

fn weekly_command(args, mutation) {
  interval_command(args, "day", availability.parse_days, mutation)
}

fn date_interval_command(args, mutation) {
  interval_command(args, "date", due.parse_date, mutation)
}

fn interval_command(args, selector_name, parse_selector, mutation) {
  use options <- result.try(parse_options(args, [selector_name, "from", "to"]))
  use selector <- result.try(
    required_parsed(options, selector_name, parse_selector) |> invalid_input,
  )
  use from <- result.try(required_value(options, "from") |> invalid_input)
  use to <- result.try(required_value(options, "to") |> invalid_input)
  use interval <- result.try(
    availability.parse_interval(from, to) |> invalid_input,
  )
  Ok(MutateAvailability(mutation(selector, interval)))
}

fn date_command(args, mutation) {
  use options <- result.try(parse_options(args, ["date"]))
  use date <- result.try(
    required_parsed(options, "date", due.parse_date) |> invalid_input,
  )
  Ok(MutateAvailability(mutation(date)))
}

// Every option has one value, so a local immutable pair parser is sufficient.
// Keeping it strict makes unknown, duplicate, and incomplete options invalid.
fn parse_options(
  args: List(String),
  allowed: List(String),
) -> Result(Options, String) {
  use options <- result.try(option_pairs(args, []) |> invalid_input)
  case list.all(options, fn(option) { list.contains(allowed, option.0) }) {
    True -> Ok(options)
    False -> Error("invalid input")
  }
}

fn option_pairs(args: List(String), reversed: Options) -> Result(Options, Nil) {
  case args {
    [] -> Ok(list.reverse(reversed))
    [name, value, ..rest] -> {
      let key = string.drop_start(name, 2)
      case
        string.starts_with(name, "--")
        && key != ""
        && !list.any(reversed, fn(option) { option.0 == key })
      {
        True -> option_pairs(rest, [#(key, value), ..reversed])
        False -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn required_value(options: Options, name: String) -> Result(String, Nil) {
  list.key_find(options, name)
}

fn optional_value(options: Options, name: String) -> Option(String) {
  required_value(options, name) |> option.from_result
}

fn value_or(options: Options, name: String, default: String) -> String {
  optional_value(options, name) |> option.unwrap(default)
}

fn required_parsed(options, name, parser) {
  use value <- result.try(required_value(options, name))
  parser(value)
}

fn optional_parsed(options, name, parser) {
  case optional_value(options, name) {
    None -> Ok(None)
    Some(value) -> parser(value) |> result.map(Some)
  }
}

fn status_filter(options) {
  case optional_value(options, "status") {
    None -> Ok(PendingOnly)
    Some(value) -> parse_status_filter(value)
  }
}

fn invalid_input(value) {
  result.map_error(value, fn(_) { "invalid input" })
}

fn parse_status_filter(value) {
  case value {
    "pending" -> Ok(PendingOnly)
    "done" -> Ok(DoneOnly)
    "all" -> Ok(AllStatuses)
    _ -> Error(Nil)
  }
}

fn parse_due_filter(value: String) -> Result(TimeFilter, Nil) {
  case value {
    "today" -> Ok(Today)
    "overdue" -> Ok(Overdue)
    value -> due.parse_date(value) |> result.map(On)
  }
}

fn parse_scheduled_exact(value: String) -> Result(TimeFilter, Nil) {
  case value {
    "today" -> Ok(Today)
    value -> due.parse_date(value) |> result.map(On)
  }
}

fn temporal_filter(exact, since, until) {
  case exact, since, until {
    None, None, None -> Ok(AnyTime)
    Some(filter), None, None -> Ok(filter)
    None, _, _ ->
      validate_range(since, until)
      |> result.map(fn(_) { DateRange(since, until) })
    _, _, _ -> Error(Nil)
  }
}

fn validate_range(since, until) -> Result(Nil, Nil) {
  case since, until {
    Some(start), Some(end) ->
      case calendar.naive_date_compare(start, end) {
        Gt -> Error(Nil)
        _ -> Ok(Nil)
      }
    _, _ -> Ok(Nil)
  }
}

pub fn help() -> Outcome {
  Outcome(
    0,
    [
      "Usage:",
      "  gleam run -- add TITLE [--estimate DURATION] [--priority 1|2|3|4|5] [--due DUE]",
      "                         [--scheduling-policy asap|spread|near_deadline]",
      "                         [--minimum-split DURATION]",
      "  gleam run -- list [--status pending|done|all] [--due today|overdue|YYYY-MM-DD]",
      "                      [--due-since YYYY-MM-DD] [--due-until YYYY-MM-DD]",
      "  gleam run -- list scheduled [--status pending|done|all] [--on today|YYYY-MM-DD]",
      "                                [--since YYYY-MM-DD] [--until YYYY-MM-DD]",
      "  gleam run -- done TASK_ID",
      "  gleam run -- schedule",
      "  gleam run -- availability weekly add|delete --day DAY[,DAY...] --from HH:MM --to HH:MM",
      "  gleam run -- availability date add|delete|set --date YYYY-MM-DD --from HH:MM --to HH:MM",
      "  gleam run -- availability date close|reset --date YYYY-MM-DD",
      "  gleam run -- availability list",
      "",
      "Defaults: estimate 0m; priority 3; scheduling policy spread; minimum split 30m; list status pending.",
      "DURATION is an integer followed by m or h. DUE is local YYYY-MM-DD[THH:MM].",
      "TASK_ID is a full UUIDv7 or an unambiguous suffix of at least 8 hex digits.",
      "DAY is mon..sun. Availability times are HH:MM from 00:00 through 24:00.",
      "Exact date filters and date ranges are mutually exclusive; ranges are inclusive.",
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

pub fn scheduling_error(error: SchedulingError) -> Outcome {
  case error {
    scheduler.SearchSpaceTooLarge ->
      grammar_error("schedule search space is too large")
    scheduler.InvalidGeneratedSchedule ->
      persistence_error("invalid generated schedule")
  }
}

pub fn domain_error(error: TaskError) -> Outcome {
  case error {
    AlreadyDone -> grammar_error("task is already completed")
    AmbiguousId ->
      grammar_error("task ID is ambiguous; use more trailing characters")
    NotFound -> grammar_error("task not found")
  }
}

pub fn added(task: Todo) -> Outcome {
  Outcome(0, ["Added task " <> short_id(task) <> ": " <> task.title], [])
}

pub fn completed(task: Todo) -> Outcome {
  Outcome(0, ["Completed task " <> short_id(task) <> ": " <> task.title], [])
}

pub fn availability_listed(value: Availability) -> Outcome {
  let availability.Availability(weekly, overrides) = value
  case weekly, overrides {
    [], [] -> Outcome(0, ["No availability configured."], [])
    _, _ -> {
      let weekly_lines =
        list.flat_map(weekly, fn(entry) {
          list.map(entry.intervals, fn(interval) {
            tab_row([
              "weekly",
              availability.weekday_string(entry.day),
              local_time.format_minute_of_day(interval.from),
              local_time.format_minute_of_day(interval.to),
            ])
          })
        })
      let override_lines =
        list.flat_map(overrides, fn(entry) {
          let date = local_time.format_date(entry.date)
          case entry.intervals {
            [] -> ["override\t" <> date <> "\tclosed"]
            intervals ->
              list.map(intervals, fn(interval) {
                tab_row([
                  "override",
                  date,
                  local_time.format_minute_of_day(interval.from),
                  local_time.format_minute_of_day(interval.to),
                ])
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

pub fn listed(
  items: List(Todo),
  status: StatusFilter,
  offset: Duration,
) -> Outcome {
  let empty_line = case status {
    PendingOnly -> "No pending tasks."
    DoneOnly -> "No done tasks."
    AllStatuses -> "No tasks."
  }
  Outcome(
    0,
    table_lines(
      items,
      empty_line,
      "ID\tSTATUS\tPRIORITY\tESTIMATE\tDUE\tTITLE",
      fn(task) { task_line(task, offset) },
    ),
    [],
  )
}

pub fn scheduled_listed(
  offset_seconds: Int,
  items: List(#(scheduling_model.SavedScheduleBlock, Todo)),
) -> Outcome {
  let offset = duration.seconds(offset_seconds)
  Outcome(
    0,
    table_lines(
      items,
      "No scheduled tasks.",
      "START\tEND\tID\tSTATUS\tTITLE",
      fn(item) {
        let #(block, task) = item
        tab_row([
          format_unix_minute(block.start_seconds, offset),
          format_unix_minute(block.end_seconds, offset),
          short_id(task),
          status_to_string(task.status),
          task.title,
        ])
      },
    ),
    [],
  )
}

fn table_lines(
  items: List(item),
  empty_line: String,
  header: String,
  render: fn(item) -> String,
) -> List(String) {
  case items {
    [] -> [empty_line]
    _ -> [header, ..list.map(items, render)]
  }
}

pub fn schedule_generated(
  generated: scheduling_model.GenerationResult,
) -> Outcome {
  let scheduling_model.GenerationResult(saved, report) = generated
  let scheduling_model.SavedSchedule(
    generated_at_seconds,
    planning_start_seconds,
    offset_seconds,
    blocks,
  ) = saved
  let scheduling_model.GenerationReport(unscheduled, excluded) = report
  let offset = duration.seconds(offset_seconds)
  let block_lines =
    table_lines(blocks, "none", "START\tEND\tTASK_ID", fn(block) {
      tab_row([
        format_unix_minute(block.start_seconds, offset),
        format_unix_minute(block.end_seconds, offset),
        task_id.short(block.task_id),
      ])
    })
  let unscheduled_lines =
    table_lines(unscheduled, "none", "TASK_ID\tMINUTES", fn(entry) {
      task_id.short(entry.task_id) <> "\t" <> int.to_string(entry.minutes)
    })
  let excluded_lines =
    table_lines(excluded, "none", "TASK_ID\tREASON", fn(entry) {
      task_id.short(entry.task_id) <> "\t" <> excluded_reason(entry.reason)
    })
  Outcome(
    0,
    list.flatten([
      [
        "SCHEDULE\tGENERATED_AT\t"
          <> format_unix_minute(generated_at_seconds, offset)
          <> "\tPLANNING_START\t"
          <> format_unix_minute(planning_start_seconds, offset),
        "BLOCKS",
      ],
      block_lines,
      ["UNSCHEDULED"],
      unscheduled_lines,
      ["EXCLUDED"],
      excluded_lines,
    ]),
    [],
  )
}

fn excluded_reason(reason: scheduling_model.ExcludedReason) -> String {
  case reason {
    scheduling_model.Completed -> "completed"
    scheduling_model.MissingEstimate -> "missing_estimate"
    scheduling_model.MissingDue -> "missing_due"
    scheduling_model.DeadlineNotAfterStart -> "deadline_not_after_start"
  }
}

fn task_line(task: Todo, offset: Duration) -> String {
  tab_row([
    short_id(task),
    status_to_string(task.status),
    int.to_string(task.priority),
    int.to_string(task.estimate_minutes) <> "m",
    due_text(task.due, offset),
    task.title,
  ])
}

fn short_id(task: Todo) -> String {
  task_id.short(task.id)
}

fn tab_row(fields: List(String)) -> String {
  string.join(fields, "\t")
}

fn format_unix_minute(seconds: Int, offset: Duration) -> String {
  local_time.format_timestamp(timestamp.from_unix_seconds(seconds), offset)
}

fn due_text(due_value: Option(Due), offset: Duration) -> String {
  case due_value {
    None -> "-"
    Some(value) -> due.format(value, offset)
  }
}
