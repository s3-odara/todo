import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar.{Date, July}
import gleam/time/duration
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/due
import tasks/domain/filter.{
  AllStatuses, AnyTime, DateRange, DoneOnly, On, Overdue, PendingOnly, Today,
  Window,
}
import tasks/domain/model.{AddValues, AlreadyDone, Done, NotFound, Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread, parse as parse_policy}
import tasks/domain/tasks
import tasks/domain/validation

fn due_at(value) {
  let assert Ok(value) = due.input(value, calendar.utc_offset)
  value
}

fn validated_add(title: String, estimate: String, priority: String) {
  validation.add(title, estimate, priority, None, "spread", "30m", fn(value) {
    due.input(value, calendar.utc_offset)
  })
}

fn validated_scheduling(policy, minimum_split) {
  validation.add("x", "0m", "3", None, policy, minimum_split, fn(value) {
    due.input(value, calendar.utc_offset)
  })
}

fn today() {
  Date(2026, July, 24)
}

fn now() {
  due.instant(due_at("2026-07-24T12:00"))
}

fn resolved(time_filter) {
  filter.resolve(time_filter, now(), calendar.utc_offset)
}

fn visible_sorted(todos, status, time_filter) {
  todos
  |> tasks.visible(status, resolved(time_filter))
  |> tasks.sorted_by_id
}

fn pending_due(id, title, canonical) {
  Todo(id, title, 0, 3, Some(due_at(canonical)), Pending, Spread, 30)
}

pub fn title_is_trimmed_test() {
  validated_add(" clean ", "0m", "3")
  |> should.equal(Ok(AddValues("clean", 0, 3, None, Spread, 30)))
}

pub fn empty_controlled_or_excessive_titles_are_rejected_test() {
  [
    "",
    "   ",
    "\tclean",
    "clean\n",
    "clean\r",
    "clean\u{0}",
    string.repeat("a", 201),
  ]
  |> list.each(fn(title) {
    validated_add(title, "0m", "3") |> should.equal(Error(Nil))
  })
}

pub fn titles_may_contain_up_to_two_hundred_codepoints_test() {
  ["a", string.repeat("a", 200)]
  |> list.each(fn(title) {
    validated_add(title, "0m", "3")
    |> should.equal(Ok(AddValues(title, 0, 3, None, Spread, 30)))
  })
}

pub fn minute_and_hour_estimates_are_normalized_to_minutes_test() {
  [
    #("0m", 0),
    #("01m", 1),
    #("+1h", 60),
    #("0h", 0),
    #("8760h", 525_600),
    #("525600m", 525_600),
  ]
  |> list.each(fn(example) {
    let #(input, minutes) = example
    validated_add("x", input, "3")
    |> should.equal(Ok(AddValues("x", minutes, 3, None, Spread, 30)))
  })
}

pub fn malformed_or_excessive_estimates_are_rejected_test() {
  ["525601m", "8761h", "1h30m", "1.5h", "3H", "-1m", "1"]
  |> list.each(fn(estimate) {
    validated_add("x", estimate, "3") |> should.equal(Error(Nil))
  })
}

pub fn priority_must_be_between_one_and_five_test() {
  [#("1", 1), #("01", 1), #("+5", 5), #("5", 5)]
  |> list.each(fn(example) {
    let #(input, priority) = example
    validated_add("x", "0m", input)
    |> should.equal(Ok(AddValues("x", 0, priority, None, Spread, 30)))
  })

  ["0", "6", "x"]
  |> list.each(fn(priority) {
    validated_add("x", "0m", priority) |> should.equal(Error(Nil))
  })
}

pub fn scheduling_policy_is_strictly_parsed_test() {
  parse_policy("asap") |> should.equal(Ok(Asap))
  parse_policy("spread") |> should.equal(Ok(Spread))
  parse_policy("near_deadline") |> should.equal(Ok(NearDeadline))
  ["ASAP", "near-deadline", "unknown"]
  |> list.each(fn(value) { parse_policy(value) |> should.equal(Error(Nil)) })
}

pub fn minimum_split_must_be_a_positive_bounded_duration_test() {
  validated_scheduling("spread", "1m")
  |> should.equal(Ok(AddValues("x", 0, 3, None, Spread, 1)))
  validated_scheduling("spread", "525600m")
  |> should.equal(Ok(AddValues("x", 0, 3, None, Spread, 525_600)))
  ["01m", "+1m"]
  |> list.each(fn(value) {
    validated_scheduling("spread", value)
    |> should.equal(Ok(AddValues("x", 0, 3, None, Spread, 1)))
  })
  ["0m", "0h", "525601m", "8761h", "-1m", "30"]
  |> list.each(fn(value) {
    validated_scheduling("spread", value) |> should.equal(Error(Nil))
  })
}

pub fn task_id_must_be_a_positive_integer_test() {
  validation.done("1") |> should.equal(Ok(1))
  validation.done("01") |> should.equal(Ok(1))
  validation.done("+1") |> should.equal(Ok(1))
  validation.done("2147483648")
  |> should.equal(Ok(2_147_483_648))

  ["0", "1x"]
  |> list.each(fn(id) { validation.done(id) |> should.equal(Error(Nil)) })
}

pub fn date_only_due_is_normalized_to_end_of_day_test() {
  due.input("2024-02-29", calendar.utc_offset)
  |> result.map(fn(value) { due.format(value, calendar.utc_offset) })
  |> should.equal(Ok("2024-02-29T23:59"))
}

pub fn local_datetime_due_is_retained_test() {
  due.input("2026-12-31T23:59", calendar.utc_offset)
  |> result.map(fn(value) { due.format(value, calendar.utc_offset) })
  |> should.equal(Ok("2026-12-31T23:59"))
}

pub fn local_due_is_stored_as_an_instant_and_presented_locally_test() {
  let japan = duration.hours(9)
  let assert Ok(stored) = due.input("2026-07-24T09:00", japan)

  timestamp.to_rfc3339(due.instant(stored), calendar.utc_offset)
  |> should.equal("2026-07-24T00:00:00Z")
  due.format(stored, japan) |> should.equal("2026-07-24T09:00")
}

pub fn invalid_calendar_or_datetime_values_are_rejected_test() {
  [
    "2023-02-29",
    "2026-04-31",
    "2026-01-01T24:00",
    "2026-01-01T12:60",
    "2026-01-01T12:00Z",
    "2026-01-01T12:00+09:00",
    "2026-01-01T12:00:01",
    "2026-01-01T12:00.1",
    "2026-01-01t12:00",
    "2026-01-01 12:00",
  ]
  |> list.each(fn(value) {
    due.input(value, calendar.utc_offset) |> should.equal(Error(Nil))
  })
}

pub fn adding_a_task_assigns_an_id_greater_than_every_existing_id_test() {
  let lower = Todo(3, "lower", 0, 3, None, Pending, Spread, 30)
  let highest = Todo(2_147_483_647, "highest", 0, 3, None, Done, Spread, 30)
  let middle = Todo(10, "middle", 0, 3, None, Pending, Spread, 30)
  let existing = [lower, highest, middle]
  let added = Todo(2_147_483_648, "new", 0, 3, None, Pending, Spread, 30)

  tasks.add(existing, AddValues("new", 0, 3, None, Spread, 30))
  |> should.equal(#([added, ..existing], added))
}

pub fn visibility_filters_without_reordering_test() {
  let first = Todo(1, "first", 0, 5, None, Pending, Spread, 30)
  let second = Todo(2, "second", 0, 1, None, Pending, Spread, 30)
  let completed = Todo(3, "completed", 0, 3, None, Done, Spread, 30)

  tasks.visible([completed, second, first], PendingOnly, resolved(AnyTime))
  |> should.equal([second, first])
}

pub fn tasks_are_sorted_by_id_without_filtering_test() {
  let first = Todo(1, "first", 0, 5, None, Pending, Spread, 30)
  let second = Todo(2, "second", 0, 1, None, Pending, Spread, 30)
  let completed = Todo(3, "completed", 0, 3, None, Done, Spread, 30)

  tasks.sorted_by_id([completed, second, first])
  |> should.equal([first, second, completed])
}

pub fn completed_tasks_are_included_when_requested_test() {
  let pending = Todo(1, "pending", 0, 3, None, Pending, Spread, 30)
  let completed = Todo(2, "completed", 0, 3, None, Done, Spread, 30)

  visible_sorted([completed, pending], AllStatuses, AnyTime)
  |> should.equal([pending, completed])
}

pub fn done_only_filters_completed_tasks_test() {
  let pending = Todo(1, "pending", 0, 3, None, Pending, Spread, 30)
  let completed = Todo(2, "completed", 0, 3, None, Done, Spread, 30)

  visible_sorted([pending, completed], DoneOnly, AnyTime)
  |> should.equal([completed])
}

pub fn relative_due_filters_resolve_to_absolute_dates_test() {
  filter.resolve(Today, now(), calendar.utc_offset)
  |> should.equal(Window(
    Some(due.instant(due_at("2026-07-24T00:00"))),
    Some(due.instant(due_at("2026-07-25T00:00"))),
  ))
  filter.resolve(Overdue, now(), calendar.utc_offset)
  |> should.equal(Window(None, Some(now())))
}

pub fn exact_due_filter_ignores_the_stored_time_test() {
  let morning = pending_due(2, "morning", "2026-07-24T00:00")
  let evening = pending_due(1, "evening", "2026-07-24T23:59")
  let later = pending_due(3, "later", "2026-07-25T00:00")

  visible_sorted([morning, later, evening], PendingOnly, On(today()))
  |> should.equal([evening, morning])
}

pub fn today_due_filter_excludes_tasks_without_a_due_date_test() {
  let undated = Todo(1, "undated", 0, 3, None, Pending, Spread, 30)
  let due_today = pending_due(2, "today", "2026-07-24T12:00")

  visible_sorted([undated, due_today], PendingOnly, Today)
  |> should.equal([due_today])
}

pub fn date_filters_use_the_current_local_offset_test() {
  let japan = duration.hours(9)
  let assert Ok(stored) = due.input("2026-07-24T00:30", japan)
  let task = Todo(1, "local date", 0, 3, Some(stored), Pending, Spread, 30)
  let window = filter.resolve(On(today()), now(), japan)

  tasks.visible([task], PendingOnly, window) |> should.equal([task])
}

pub fn overdue_is_strictly_before_now_test() {
  let yesterday = pending_due(1, "yesterday", "2026-07-23T23:59")
  let earlier_today = pending_due(2, "earlier", "2026-07-24T11:59")
  let due_now = pending_due(3, "now", "2026-07-24T12:00")

  visible_sorted([due_now, earlier_today, yesterday], PendingOnly, Overdue)
  |> should.equal([yesterday, earlier_today])
}

pub fn due_range_includes_both_boundaries_test() {
  let start = pending_due(1, "start", "2026-07-24T23:59")
  let end = pending_due(2, "end", "2026-07-25T23:59")
  let outside = pending_due(3, "outside", "2026-07-26T00:00")
  let assert Ok(until) = due.parse_date("2026-07-25")

  visible_sorted(
    [outside, end, start],
    PendingOnly,
    DateRange(Some(today()), Some(until)),
  )
  |> should.equal([start, end])
}

pub fn one_sided_due_ranges_are_inclusive_test() {
  let before = pending_due(1, "before", "2026-07-23T00:00")
  let boundary = pending_due(2, "boundary", "2026-07-24T00:00")
  let after = pending_due(3, "after", "2026-07-25T00:00")

  visible_sorted(
    [after, boundary, before],
    PendingOnly,
    DateRange(Some(today()), None),
  )
  |> should.equal([boundary, after])
  visible_sorted(
    [after, boundary, before],
    PendingOnly,
    DateRange(None, Some(today())),
  )
  |> should.equal([before, boundary])
}

pub fn status_and_due_filters_are_combined_with_and_test() {
  let pending = pending_due(1, "pending", "2026-07-23T00:00")
  let completed =
    Todo(2, "done", 0, 3, Some(due_at("2026-07-23T00:00")), Done, Spread, 30)

  visible_sorted([pending, completed], DoneOnly, Overdue)
  |> should.equal([completed])
}

pub fn parse_date_requires_a_real_zero_padded_date_test() {
  due.parse_date("2026-07-24") |> should.equal(Ok(today()))
  ["2026-7-24", "2026-02-29", "0000-01-01", "2026-04-31"]
  |> list.each(fn(value) { due.parse_date(value) |> should.equal(Error(Nil)) })
}

pub fn completing_a_pending_task_preserves_the_other_tasks_test() {
  let selected = Todo(2, "selected", 0, 5, None, Pending, Spread, 30)
  let other = Todo(1, "other", 0, 3, None, Pending, Spread, 30)

  tasks.complete([selected, other], 2)
  |> should.equal(
    Ok(#(
      [Todo(2, "selected", 0, 5, None, Done, Spread, 30), other],
      Todo(2, "selected", 0, 5, None, Done, Spread, 30),
    )),
  )
}

pub fn a_completed_task_cannot_be_completed_again_test() {
  let completed = Todo(1, "done", 0, 3, None, Done, Spread, 30)

  tasks.complete([completed], 1) |> should.equal(Error(AlreadyDone))
}

pub fn an_unknown_task_cannot_be_completed_test() {
  let task = Todo(1, "existing", 0, 3, None, Pending, Spread, 30)

  tasks.complete([task], 2) |> should.equal(Error(NotFound))
}
