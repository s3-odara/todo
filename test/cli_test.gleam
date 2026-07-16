import gleam/list
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, July}
import gleam/time/duration
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability
import tasks/domain/due
import tasks/domain/filter.{
  AllStatuses, DoneOnly, Exact, ListFilter, Overdue, PendingOnly, Range, Today,
}
import tasks/domain/model.{Done, Pending, Todo, ValidatedAdd}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import todo_app/cli
import todo_app/runtime
import todo_app/store.{Store}

fn today() {
  Date(2026, July, 24)
}

fn due_at(value) {
  let assert Ok(value) = due.input(value, calendar.utc_offset)
  value
}

fn clock() {
  #(due.instant(due_at("2026-07-24T12:00")), calendar.utc_offset)
}

fn parse(args) {
  cli.parse(args, fn(value) { due.input(value, calendar.utc_offset) })
}

fn run(args, store) {
  case parse(args) {
    Ok(command) -> runtime.run(command, store, clock)
    Error(message) -> cli.grammar_error(message)
  }
}

fn state_with(tasks) {
  AppState(1, tasks, availability.empty(), None)
}

fn store_with(tasks) {
  Store(fn() { Ok(state_with(tasks)) }, fn(_) { Ok(Nil) })
}

fn clock_must_not_run() {
  panic as "clock must not run for this command"
}

pub fn help_is_selected_when_no_command_or_a_help_flag_is_given_test() {
  [[], ["--help"], ["add", "--help"], ["list", "--help"], ["done", "--help"]]
  |> list.each(fn(args) { parse(args) |> should.equal(Ok(cli.Help)) })
}

pub fn non_list_commands_do_not_read_the_clock_test() {
  runtime.run(cli.Help, store_with([]), clock_must_not_run)
  |> should.equal(cli.help())
  runtime.run(
    cli.Add(ValidatedAdd("x", 0, 3, None, Spread, 30)),
    store_with([]),
    clock_must_not_run,
  )
  |> should.equal(cli.Outcome(0, ["Added task 1: x"], []))
}

pub fn help_lists_the_available_commands_test() {
  cli.help()
  |> should.equal(
    cli.Outcome(
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
    ),
  )
}

pub fn add_uses_default_estimate_and_priority_test() {
  parse(["add", "x"])
  |> should.equal(Ok(cli.Add(ValidatedAdd("x", 0, 3, None, Spread, 30))))
}

pub fn add_scheduling_defaults_are_applied_test() {
  parse(["add", "x"])
  |> should.equal(Ok(cli.Add(ValidatedAdd("x", 0, 3, None, Spread, 30))))
}

pub fn add_scheduling_options_are_parsed_test() {
  parse([
    "add",
    "x",
    "--minimum-split",
    "45m",
    "--scheduling-policy",
    "asap",
  ])
  |> should.equal(Ok(cli.Add(ValidatedAdd("x", 0, 3, None, Asap, 45))))

  parse(["add", "x", "--scheduling-policy", "near_deadline"])
  |> should.equal(Ok(cli.Add(ValidatedAdd("x", 0, 3, None, NearDeadline, 30))))
}

pub fn invalid_scheduling_options_are_rejected_test() {
  [
    ["add", "x", "--scheduling-policy", "unknown"],
    ["add", "x", "--minimum-split", "0m"],
    ["add", "x", "--minimum-split", "-1m"],
    ["add", "x", "--minimum-split", "30"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })

  [
    ["add", "x", "--scheduling-policy"],
    ["add", "x", "--minimum-split"],
    [
      "add",
      "x",
      "--scheduling-policy",
      "asap",
      "--scheduling-policy",
      "spread",
    ],
    ["add", "x", "--minimum-split", "30m", "--minimum-split", "1h"],
  ]
  |> list.each(fn(args) {
    parse(args)
    |> should.equal(Error("invalid, duplicate, or missing option"))
  })
}

pub fn due_parser_is_only_called_when_due_is_present_test() {
  cli.parse(["add", "x"], fn(_) { panic as "due parser must not run" })
  |> should.equal(Ok(cli.Add(ValidatedAdd("x", 0, 3, None, Spread, 30))))
}

pub fn add_options_can_be_given_in_any_order_test() {
  parse([
    "add",
    "x",
    "--due",
    "2026-01-01",
    "--priority",
    "5",
    "--estimate",
    "2h",
  ])
  |> should.equal(
    Ok(
      cli.Add(ValidatedAdd(
        "x",
        120,
        5,
        Some(due_at("2026-01-01T23:59")),
        Spread,
        30,
      )),
    ),
  )
}

pub fn duplicate_add_options_are_rejected_test() {
  [
    ["add", "x", "--estimate", "0m", "--estimate", "1h"],
    ["add", "x", "--priority", "3", "--priority", "4"],
    ["add", "x", "--due", "2026-01-01", "--due", "2026-01-02"],
  ]
  |> list.each(fn(args) {
    parse(args)
    |> should.equal(Error("invalid, duplicate, or missing option"))
  })
}

pub fn unknown_or_incomplete_add_options_are_rejected_test() {
  [["add", "x", "--unknown", "y"], ["add", "x", "--estimate"]]
  |> list.each(fn(args) {
    parse(args)
    |> should.equal(Error("invalid, duplicate, or missing option"))
  })
}

pub fn invalid_command_shapes_are_rejected_test() {
  [
    ["wat"],
    ["done"],
    ["done", "1", "extra"],
  ]
  |> list.each(fn(args) {
    parse(args) |> should.equal(Error("invalid command or arguments"))
  })
}

pub fn done_parses_its_id_test() {
  parse(["done", "1"])
  |> should.equal(Ok(cli.RunDone(1)))
}

pub fn list_status_options_parse_to_typed_filters_test() {
  parse(["list"])
  |> should.equal(Ok(cli.List(ListFilter(PendingOnly, None))))
  parse(["list", "--done"])
  |> should.equal(Ok(cli.List(ListFilter(DoneOnly, None))))
  parse(["list", "--all"])
  |> should.equal(Ok(cli.List(ListFilter(AllStatuses, None))))
}

pub fn list_due_options_parse_to_typed_filters_test() {
  parse(["list", "--due", "today"])
  |> should.equal(Ok(cli.List(ListFilter(PendingOnly, Some(Today)))))
  parse(["list", "--due", "overdue"])
  |> should.equal(Ok(cli.List(ListFilter(PendingOnly, Some(Overdue)))))
  parse(["list", "--due", "2026-07-24"])
  |> should.equal(Ok(cli.List(ListFilter(PendingOnly, Some(Exact(today()))))))
}

pub fn one_sided_list_ranges_parse_to_typed_filters_test() {
  parse(["list", "--due-since", "2026-07-24"])
  |> should.equal(
    Ok(cli.List(ListFilter(PendingOnly, Some(Range(Some(today()), None))))),
  )
  parse(["list", "--due-until", "2026-07-24"])
  |> should.equal(
    Ok(cli.List(ListFilter(PendingOnly, Some(Range(None, Some(today())))))),
  )
}

pub fn status_and_exact_due_options_are_order_independent_test() {
  let expected = Ok(cli.List(ListFilter(AllStatuses, Some(Exact(today())))))

  parse(["list", "--all", "--due", "2026-07-24"])
  |> should.equal(expected)
  parse(["list", "--due", "2026-07-24", "--all"])
  |> should.equal(expected)
}

pub fn list_range_options_are_order_independent_test() {
  let assert Ok(until) = due.parse_date("2026-07-25")
  let expected =
    Ok(cli.List(ListFilter(DoneOnly, Some(Range(Some(today()), Some(until))))))

  parse([
    "list",
    "--done",
    "--due-since",
    "2026-07-24",
    "--due-until",
    "2026-07-25",
  ])
  |> should.equal(expected)
  parse([
    "list",
    "--due-until",
    "2026-07-25",
    "--due-since",
    "2026-07-24",
    "--done",
  ])
  |> should.equal(expected)
}

pub fn duplicate_list_options_are_invalid_input_test() {
  [
    ["list", "--done", "--done"],
    ["list", "--all", "--all"],
    ["list", "--due", "today", "--due", "overdue"],
    ["list", "--due-since", "2026-07-24", "--due-since", "2026-07-25"],
    ["list", "--due-until", "2026-07-24", "--due-until", "2026-07-25"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })
}

pub fn conflicting_list_options_are_invalid_in_either_order_test() {
  [
    ["list", "--done", "--all"],
    ["list", "--all", "--done"],
    ["list", "--due", "today", "--due-since", "2026-07-24"],
    ["list", "--due-since", "2026-07-24", "--due", "today"],
    ["list", "--due", "today", "--due-until", "2026-07-24"],
    ["list", "--due-until", "2026-07-24", "--due", "today"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })
}

pub fn invalid_list_values_and_missing_values_are_invalid_input_test() {
  [
    ["list", "--due"],
    ["list", "--due-since"],
    ["list", "--due-until"],
    ["list", "--unknown"],
    ["list", "--due", "yesterday"],
    ["list", "--due", "2026-02-29"],
    ["list", "--due-since", "today"],
    ["list", "--due-until", "overdue"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })
}

pub fn reversed_due_range_is_invalid_input_test() {
  parse([
    "list",
    "--due-since",
    "2026-07-25",
    "--due-until",
    "2026-07-24",
  ])
  |> should.equal(Error("invalid input"))
}

pub fn list_input_errors_use_the_cli_grammar_error_contract_test() {
  run(["list", "--done", "--all"], store_with([]))
  |> should.equal(cli.Outcome(2, [], ["Error: invalid input"]))
}

pub fn an_empty_list_uses_the_status_specific_message_test() {
  let empty = store_with([])

  run(["list"], empty)
  |> should.equal(cli.Outcome(0, ["No pending tasks."], []))
  run(["list", "--done"], empty)
  |> should.equal(cli.Outcome(0, ["No done tasks."], []))
  run(["list", "--all"], empty)
  |> should.equal(cli.Outcome(0, ["No tasks."], []))
}

pub fn tasks_are_rendered_as_tab_separated_rows_test() {
  let store = store_with([Todo(1, "x", 5, 3, None, Pending, Spread, 30)])

  run(["list"], store)
  |> should.equal(
    cli.Outcome(
      0,
      ["ID\tSTATUS\tPRIORITY\tESTIMATE\tDUE\tTITLE", "1\tpending\t3\t5m\t-\tx"],
      [],
    ),
  )
}

pub fn stored_due_is_rendered_with_the_current_local_offset_test() {
  let japan = duration.hours(9)
  let assert Ok(stored) = due.input("2026-07-24T09:00", japan)
  let command = cli.List(ListFilter(PendingOnly, None))

  runtime.run(
    command,
    store_with([Todo(1, "x", 0, 3, Some(stored), Pending, Spread, 30)]),
    fn() { #(due.instant(due_at("2026-07-24T12:00")), japan) },
  )
  |> should.equal(
    cli.Outcome(
      0,
      [
        "ID\tSTATUS\tPRIORITY\tESTIMATE\tDUE\tTITLE",
        "1\tpending\t3\t0m\t2026-07-24T09:00\tx",
      ],
      [],
    ),
  )
}

pub fn invalid_input_is_reported_on_stderr_test() {
  run(["add", "x", "--priority", "9"], store_with([]))
  |> should.equal(cli.Outcome(2, [], ["Error: invalid input"]))
}

pub fn an_unknown_task_is_reported_on_stderr_test() {
  let store = store_with([Todo(1, "x", 5, 3, None, Pending, Spread, 30)])

  run(["done", "99"], store)
  |> should.equal(cli.Outcome(2, [], ["Error: task not found"]))
}

pub fn an_already_completed_task_is_reported_on_stderr_test() {
  let store = store_with([Todo(1, "x", 5, 3, None, Done, Spread, 30)])

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
  let store = store_with([Todo(1, "x", 0, 3, None, Pending, Spread, 30)])

  run(["done", "1"], store)
  |> should.equal(cli.Outcome(0, ["Completed task 1: x"], []))
}
