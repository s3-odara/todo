import datebook/weekday.{Friday, Monday}
import gleam/list
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, July}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability
import tasks/domain/due
import tasks/domain/filter.{
  AllStatuses, AnyTime, DateRange, DoneOnly, On, Overdue, PendingOnly, Today,
}
import tasks/domain/model.{AddValues, Done, Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/model as scheduling_model
import test_support.{id}
import todo_app/cli
import todo_app/runtime

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
  cli.parse_with_id(
    args,
    fn(value) { due.input(value, calendar.utc_offset) },
    fn() { id(1) },
  )
}

fn run(args, state) {
  case parse(args) {
    Ok(command) -> {
      let #(now, offset) = clock()
      runtime.execute(command, state, now, offset).outcome
    }
    Error(message) -> cli.grammar_error(message)
  }
}

fn state_with(tasks) {
  AppState(tasks, availability.empty(), None)
}

fn run_command(command, state) {
  let #(now, offset) = clock()
  runtime.execute(command, state, now, offset).outcome
}

pub fn help_is_selected_when_no_command_or_a_help_flag_is_given_test() {
  [
    [],
    ["--help"],
    ["add", "--help"],
    ["list", "--help"],
    ["list", "scheduled", "--help"],
    ["availability", "weekly", "add", "--help"],
    ["done", "--help"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Ok(cli.Help)) })
}

pub fn commands_ignore_time_when_their_behavior_is_not_time_relative_test() {
  run_command(cli.Help, state_with([]))
  |> should.equal(cli.help())
  run_command(
    cli.Add(id(1), AddValues("x", 0, 3, None, Spread, 30)),
    state_with([]),
  )
  |> should.equal(cli.Outcome(0, ["Added task 00000001: x"], []))
}

pub fn help_lists_the_available_commands_test() {
  let cli.Outcome(code, lines, errors) = cli.help()

  code |> should.equal(0)
  errors |> should.equal([])
  lines |> list.contains("Usage:") |> should.be_true
  lines
  |> list.contains("  gleam run -- done TASK_ID")
  |> should.be_true
  lines
  |> list.contains("  gleam run -- schedule")
  |> should.be_true
  lines
  |> list.contains("  gleam run -- availability list")
  |> should.be_true
}

pub fn add_defaults_are_applied_test() {
  parse(["add", "x"])
  |> should.equal(Ok(cli.Add(id(1), AddValues("x", 0, 3, None, Spread, 30))))
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
  |> should.equal(Ok(cli.Add(id(1), AddValues("x", 0, 3, None, Asap, 45))))

  parse(["add", "x", "--scheduling-policy", "near_deadline"])
  |> should.equal(
    Ok(cli.Add(id(1), AddValues("x", 0, 3, None, NearDeadline, 30))),
  )
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
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })
}

pub fn due_parser_is_only_called_when_due_is_present_test() {
  cli.parse_with_id(
    ["add", "x"],
    fn(_) { panic as "due parser must not run" },
    fn() { id(1) },
  )
  |> should.equal(Ok(cli.Add(id(1), AddValues("x", 0, 3, None, Spread, 30))))
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
    Ok(cli.Add(
      id(1),
      AddValues("x", 120, 5, Some(due_at("2026-01-01T23:59")), Spread, 30),
    )),
  )
}

pub fn duplicate_add_options_are_rejected_test() {
  [
    ["add", "x", "--estimate", "0m", "--estimate", "1h"],
    ["add", "x", "--priority", "3", "--priority", "4"],
    ["add", "x", "--due", "2026-01-01", "--due", "2026-01-02"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })
}

pub fn unknown_or_incomplete_add_options_are_rejected_test() {
  [["add", "x", "--unknown", "y"], ["add", "x", "--estimate"]]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })
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

pub fn availability_commands_parse_to_typed_mutations_test() {
  let date = Date(2026, July, 20)
  parse(["availability", "list"])
  |> should.equal(Ok(cli.AvailabilityList))
  parse([
    "availability", "weekly", "add", "--day", "mon,fri", "--from", "09:00",
    "--to", "12:00",
  ])
  |> should.equal(
    Ok(
      cli.MutateAvailability(availability.AddWeekly(
        [Monday, Friday],
        availability.Interval(540, 720),
      )),
    ),
  )
  parse([
    "availability", "weekly", "delete", "--day", "mon", "--from", "09:00",
    "--to", "12:00",
  ])
  |> should.equal(
    Ok(
      cli.MutateAvailability(availability.DeleteWeekly(
        [Monday],
        availability.Interval(540, 720),
      )),
    ),
  )
  parse([
    "availability", "date", "set", "--date", "2026-07-20", "--from", "09:00",
    "--to", "12:00",
  ])
  |> should.equal(
    Ok(
      cli.MutateAvailability(availability.SetDate(
        date,
        availability.Interval(540, 720),
      )),
    ),
  )
  parse(["availability", "date", "close", "--date", "2026-07-20"])
  |> should.equal(Ok(cli.MutateAvailability(availability.CloseDate(date))))
  parse(["availability", "date", "reset", "--date", "2026-07-20"])
  |> should.equal(Ok(cli.MutateAvailability(availability.ResetDate(date))))
}

pub fn invalid_availability_shapes_are_rejected_test() {
  [
    [
      "availability",
      "weekly",
      "add",
      "--day",
      "mon,mon",
      "--from",
      "09:00",
      "--to",
      "10:00",
    ],
    [
      "availability", "weekly", "add", "--day", "wat", "--from", "09:00", "--to",
      "10:00",
    ],
    [
      "availability", "weekly", "add", "--day", "mon", "--from", "24:00", "--to",
      "24:00",
    ],
    [
      "availability", "weekly", "delete", "--day", "mon", "--from", "10:00",
      "--to", "09:00",
    ],
    [
      "availability", "weekly", "add", "--day", "mon", "--day", "fri", "--from",
      "09:00", "--to", "10:00",
    ],
    ["availability", "date", "set", "--date", "2026-07-20", "--from", "09:00"],
    ["availability", "date", "close", "--date", "2026-07-20", "--from", "09:00"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })

  // Old ambiguous scope syntax is intentionally unsupported.
  parse([
    "availability", "add", "--day", "mon", "--from", "09:00", "--to", "10:00",
  ])
  |> should.equal(Error("invalid command or arguments"))
}

pub fn done_parses_its_id_test() {
  parse(["done", "00000001"])
  |> should.equal(Ok(cli.RunDone("00000001")))
}

pub fn list_status_options_parse_to_typed_filters_test() {
  parse(["list"])
  |> should.equal(Ok(cli.ListTasks(PendingOnly, AnyTime)))
  parse(["list", "--status", "done"])
  |> should.equal(Ok(cli.ListTasks(DoneOnly, AnyTime)))
  parse(["list", "--status", "all"])
  |> should.equal(Ok(cli.ListTasks(AllStatuses, AnyTime)))
}

pub fn schedule_and_scheduled_list_commands_parse_test() {
  parse(["schedule"]) |> should.equal(Ok(cli.GenerateSchedule))
  parse(["schedule", "extra"])
  |> should.equal(Error("invalid command or arguments"))

  parse(["list", "scheduled"])
  |> should.equal(Ok(cli.ListScheduled(PendingOnly, AnyTime)))
  parse(["list", "scheduled", "--on", "today", "--status", "done"])
  |> should.equal(Ok(cli.ListScheduled(DoneOnly, Today)))
  parse(["list", "scheduled", "--on", "2026-07-24", "--status", "all"])
  |> should.equal(Ok(cli.ListScheduled(AllStatuses, On(today()))))
  parse(["list", "scheduled", "--since", "2026-07-24"])
  |> should.equal(
    Ok(cli.ListScheduled(PendingOnly, DateRange(Some(today()), None))),
  )
  parse(["list", "scheduled", "--until", "2026-07-24"])
  |> should.equal(
    Ok(cli.ListScheduled(PendingOnly, DateRange(None, Some(today())))),
  )
}

pub fn scheduled_list_conflicts_and_invalid_ranges_are_rejected_test() {
  [
    ["list", "scheduled", "--on", "today", "--since", "2026-07-24"],
    ["list", "scheduled", "--since", "2026-07-25", "--until", "2026-07-24"],
    ["list", "scheduled", "--on", "wat"],
    ["list", "scheduled", "--since"],
    ["list", "scheduled", "--on", "today", "--on", "today"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })

  // Compatibility aliases would retain the old parser's ambiguity.
  [["list", "--scheduled"], ["list", "--done"], ["list", "--all"]]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })
}

pub fn explicit_scheduled_list_ignores_the_supplied_current_time_test() {
  [AnyTime, On(today()), DateRange(Some(today()), None)]
  |> list.each(fn(time_filter) {
    run_command(cli.ListScheduled(PendingOnly, time_filter), state_with([]))
    |> should.equal(cli.Outcome(0, ["No scheduled tasks."], []))
  })
}

pub fn list_due_options_parse_to_typed_filters_test() {
  parse(["list", "--due", "today"])
  |> should.equal(Ok(cli.ListTasks(PendingOnly, Today)))
  parse(["list", "--due", "overdue"])
  |> should.equal(Ok(cli.ListTasks(PendingOnly, Overdue)))
  parse(["list", "--due", "2026-07-24"])
  |> should.equal(Ok(cli.ListTasks(PendingOnly, On(today()))))
}

pub fn one_sided_list_ranges_parse_to_typed_filters_test() {
  parse(["list", "--due-since", "2026-07-24"])
  |> should.equal(
    Ok(cli.ListTasks(PendingOnly, DateRange(Some(today()), None))),
  )
  parse(["list", "--due-until", "2026-07-24"])
  |> should.equal(
    Ok(cli.ListTasks(PendingOnly, DateRange(None, Some(today())))),
  )
}

pub fn status_and_exact_due_options_are_order_independent_test() {
  let expected = Ok(cli.ListTasks(AllStatuses, On(today())))

  parse(["list", "--status", "all", "--due", "2026-07-24"])
  |> should.equal(expected)
  parse(["list", "--due", "2026-07-24", "--status", "all"])
  |> should.equal(expected)
}

pub fn list_range_options_are_order_independent_test() {
  let assert Ok(until) = due.parse_date("2026-07-25")
  let expected =
    Ok(cli.ListTasks(DoneOnly, DateRange(Some(today()), Some(until))))

  parse([
    "list",
    "--status",
    "done",
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
    "--status",
    "done",
  ])
  |> should.equal(expected)
}

pub fn duplicate_list_options_are_invalid_input_test() {
  [
    ["list", "--status", "done", "--status", "all"],
    ["list", "--due", "today", "--due", "overdue"],
    ["list", "--due-since", "2026-07-24", "--due-since", "2026-07-25"],
    ["list", "--due-until", "2026-07-24", "--due-until", "2026-07-25"],
  ]
  |> list.each(fn(args) { parse(args) |> should.equal(Error("invalid input")) })
}

pub fn conflicting_list_options_are_invalid_in_either_order_test() {
  [
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
  run(["list", "--status", "unknown"], state_with([]))
  |> should.equal(cli.Outcome(2, [], ["Error: invalid input"]))
}

pub fn availability_formatter_is_stable_and_marks_closed_overrides_test() {
  let value =
    availability.Availability(
      [
        availability.WeeklyAvailability(Monday, [
          availability.Interval(540, 720),
        ]),
      ],
      [availability.DateOverride(Date(2026, July, 21), [])],
    )
  cli.availability_listed(value)
  |> should.equal(
    cli.Outcome(
      0,
      [
        "weekly\tmon\t09:00\t12:00",
        "override\t2026-07-21\tclosed",
      ],
      [],
    ),
  )
  cli.availability_listed(availability.empty())
  |> should.equal(cli.Outcome(0, ["No availability configured."], []))
}

pub fn an_empty_list_uses_the_status_specific_message_test() {
  let empty = state_with([])

  run(["list"], empty)
  |> should.equal(cli.Outcome(0, ["No pending tasks."], []))
  run(["list", "--status", "done"], empty)
  |> should.equal(cli.Outcome(0, ["No done tasks."], []))
  run(["list", "--status", "all"], empty)
  |> should.equal(cli.Outcome(0, ["No tasks."], []))
}

pub fn tasks_are_rendered_as_tab_separated_rows_test() {
  let state = state_with([Todo(id(1), "x", 5, 3, None, Pending, Spread, 30)])

  run(["list"], state)
  |> should.equal(
    cli.Outcome(
      0,
      [
        "ID\tSTATUS\tPRIORITY\tESTIMATE\tDUE\tTITLE",
        "00000001\tpending\t3\t5m\t-\tx",
      ],
      [],
    ),
  )
}

pub fn scheduled_rows_use_the_saved_offset_and_current_task_test() {
  let start = due.instant(due_at("2026-07-24T00:00"))
  let end = timestamp.add(start, duration.minutes(30))
  let #(start_seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(start)
  let #(end_seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(end)
  let task = Todo(id(1), "x", 30, 3, None, Done, Spread, 30)
  let schedule =
    scheduling_model.SavedSchedule(start_seconds, start_seconds, 32_400, [
      scheduling_model.SavedScheduleBlock(id(1), start_seconds, end_seconds),
    ])
  let state = AppState([task], availability.empty(), Some(schedule))
  let #(now, offset) = clock()

  runtime.execute(cli.ListScheduled(AllStatuses, AnyTime), state, now, offset).outcome
  |> should.equal(
    cli.Outcome(
      0,
      [
        "START\tEND\tID\tSTATUS\tTITLE",
        "2026-07-24T09:00\t2026-07-24T09:30\t00000001\tdone\tx",
      ],
      [],
    ),
  )
}

pub fn stored_due_is_rendered_with_the_current_local_offset_test() {
  let japan = duration.hours(9)
  let assert Ok(stored) = due.input("2026-07-24T09:00", japan)
  let command = cli.ListTasks(PendingOnly, AnyTime)

  runtime.execute(
    command,
    state_with([Todo(id(1), "x", 0, 3, Some(stored), Pending, Spread, 30)]),
    due.instant(due_at("2026-07-24T12:00")),
    japan,
  ).outcome
  |> should.equal(
    cli.Outcome(
      0,
      [
        "ID\tSTATUS\tPRIORITY\tESTIMATE\tDUE\tTITLE",
        "00000001\tpending\t3\t0m\t2026-07-24T09:00\tx",
      ],
      [],
    ),
  )
}

pub fn invalid_input_is_reported_on_stderr_test() {
  run(["add", "x", "--priority", "9"], state_with([]))
  |> should.equal(cli.Outcome(2, [], ["Error: invalid input"]))
}

pub fn an_unknown_task_is_reported_on_stderr_test() {
  let state = state_with([Todo(id(1), "x", 5, 3, None, Pending, Spread, 30)])

  run(["done", "00000099"], state)
  |> should.equal(cli.Outcome(2, [], ["Error: task not found"]))
}

pub fn an_already_completed_task_is_reported_on_stderr_test() {
  let state = state_with([Todo(id(1), "x", 5, 3, None, Done, Spread, 30)])

  run(["done", "00000001"], state)
  |> should.equal(cli.Outcome(2, [], ["Error: task is already completed"]))
}

pub fn a_failed_command_does_not_mark_state_as_changed_test() {
  let state = state_with([Todo(id(1), "x", 5, 3, None, Pending, Spread, 30)])
  let #(now, offset) = clock()
  let execution = runtime.execute(cli.RunDone("00000099"), state, now, offset)

  execution.changed |> should.be_false
  execution.state |> should.equal(state)
}

pub fn mutations_mark_only_structural_changes_for_persistence_test() {
  let state = state_with([])
  let #(now, offset) = clock()
  let added =
    runtime.execute(
      cli.Add(id(1), AddValues("x", 0, 3, None, Spread, 30)),
      state,
      now,
      offset,
    )
  let assert Ok(date) = due.parse_date("2026-07-20")
  let reset =
    runtime.execute(
      cli.MutateAvailability(availability.ResetDate(date)),
      state,
      now,
      offset,
    )

  added.changed |> should.be_true
  added.state.tasks
  |> should.equal([Todo(id(1), "x", 0, 3, None, Pending, Spread, 30)])
  reset.changed |> should.be_false
  reset.state |> should.equal(state)
}

pub fn adding_a_task_reports_its_id_and_title_test() {
  run(["add", "x"], state_with([]))
  |> should.equal(cli.Outcome(0, ["Added task 00000001: x"], []))
}

pub fn completing_a_task_updates_state_and_reports_the_task_test() {
  let state = state_with([Todo(id(1), "x", 0, 3, None, Pending, Spread, 30)])
  let #(now, offset) = clock()
  let execution = runtime.execute(cli.RunDone("00000001"), state, now, offset)

  execution.outcome
  |> should.equal(cli.Outcome(0, ["Completed task 00000001: x"], []))
  execution.changed |> should.be_true
  execution.state.tasks
  |> should.equal([Todo(id(1), "x", 0, 3, None, Done, Spread, 30)])
}

pub fn schedule_generation_updates_the_snapshot_test() {
  let state = state_with([])
  let #(now, offset) = clock()
  let execution = runtime.execute(cli.GenerateSchedule, state, now, offset)

  execution.changed |> should.be_true
  execution.state.current_schedule |> should.be_some
}
