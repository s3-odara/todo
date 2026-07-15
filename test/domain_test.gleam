import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/calendar.{Date, July}
import gleeunit/should
import tasks/domain/due
import tasks/domain/filter.{
  AllStatuses, Before, DoneOnly, Exact, ListFilter, On, Overdue, PendingOnly,
  Range, ResolvedListFilter, Today,
}
import tasks/domain/model.{
  AlreadyDone, Done, Due, NotFound, Pending, Todo, ValidatedAdd,
}
import tasks/domain/tasks
import tasks/domain/validation

fn validated_add(title: String, estimate: String, priority: String) {
  validation.add(title, estimate, priority, None)
}

fn today() {
  Date(2026, July, 24)
}

fn pending_filter() {
  ListFilter(PendingOnly, None)
}

fn resolved(criteria) {
  filter.resolve(criteria, today())
}

fn pending_due(id, title, canonical) {
  Todo(id, title, 0, 3, Some(Due(canonical)), Pending)
}

pub fn title_is_trimmed_test() {
  validated_add(" clean ", "0m", "3")
  |> should.equal(Ok(ValidatedAdd("clean", 0, 3, None)))
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
    |> should.equal(Ok(ValidatedAdd(title, 0, 3, None)))
  })
}

pub fn minute_and_hour_estimates_are_normalized_to_minutes_test() {
  [#("0m", 0), #("0h", 0), #("8760h", 525_600), #("525600m", 525_600)]
  |> list.each(fn(example) {
    let #(input, minutes) = example
    validated_add("x", input, "3")
    |> should.equal(Ok(ValidatedAdd("x", minutes, 3, None)))
  })
}

pub fn malformed_or_excessive_estimates_are_rejected_test() {
  ["525601m", "8761h", "01m", "1h30m", "1.5h", "3H", "-1m", "1"]
  |> list.each(fn(estimate) {
    validated_add("x", estimate, "3") |> should.equal(Error(Nil))
  })
}

pub fn priority_must_be_between_one_and_five_test() {
  [#("1", 1), #("5", 5)]
  |> list.each(fn(example) {
    let #(input, priority) = example
    validated_add("x", "0m", input)
    |> should.equal(Ok(ValidatedAdd("x", 0, priority, None)))
  })

  ["0", "6", "01", "x"]
  |> list.each(fn(priority) {
    validated_add("x", "0m", priority) |> should.equal(Error(Nil))
  })
}

pub fn task_id_must_be_a_positive_ascii_decimal_test() {
  validation.done("1") |> should.equal(Ok(1))
  validation.done("2147483648")
  |> should.equal(Ok(2_147_483_648))

  ["0", "01", "1x"]
  |> list.each(fn(id) { validation.done(id) |> should.equal(Error(Nil)) })
}

pub fn date_only_due_is_normalized_to_end_of_day_test() {
  due.input("2024-02-29") |> should.equal(Ok(Due("2024-02-29T23:59")))
}

pub fn local_datetime_due_is_retained_test() {
  due.input("2026-12-31T23:59")
  |> should.equal(Ok(Due("2026-12-31T23:59")))
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
  |> list.each(fn(value) { due.input(value) |> should.equal(Error(Nil)) })
}

pub fn adding_a_task_assigns_an_id_greater_than_every_existing_id_test() {
  let lower = Todo(3, "lower", 0, 3, None, Pending)
  let highest = Todo(2_147_483_647, "highest", 0, 3, None, Done)
  let middle = Todo(10, "middle", 0, 3, None, Pending)
  let existing = [lower, highest, middle]
  let added = Todo(2_147_483_648, "new", 0, 3, None, Pending)

  tasks.add(existing, ValidatedAdd("new", 0, 3, None))
  |> should.equal(#([added, ..existing], added))
}

pub fn pending_tasks_are_listed_in_id_order_test() {
  let first = Todo(1, "first", 0, 5, None, Pending)
  let second = Todo(2, "second", 0, 1, None, Pending)
  let completed = Todo(3, "completed", 0, 3, None, Done)

  tasks.visible_sorted([completed, second, first], resolved(pending_filter()))
  |> should.equal([first, second])
}

pub fn completed_tasks_are_included_when_requested_test() {
  let pending = Todo(1, "pending", 0, 3, None, Pending)
  let completed = Todo(2, "completed", 0, 3, None, Done)

  tasks.visible_sorted(
    [completed, pending],
    resolved(ListFilter(AllStatuses, None)),
  )
  |> should.equal([pending, completed])
}

pub fn done_only_filters_completed_tasks_test() {
  let pending = Todo(1, "pending", 0, 3, None, Pending)
  let completed = Todo(2, "completed", 0, 3, None, Done)

  tasks.visible_sorted(
    [pending, completed],
    resolved(ListFilter(DoneOnly, None)),
  )
  |> should.equal([completed])
}

pub fn relative_due_filters_resolve_to_absolute_dates_test() {
  filter.resolve(ListFilter(PendingOnly, Some(Today)), today())
  |> should.equal(ResolvedListFilter(PendingOnly, Some(On(today()))))
  filter.resolve(ListFilter(PendingOnly, Some(Overdue)), today())
  |> should.equal(ResolvedListFilter(PendingOnly, Some(Before(today()))))
}

pub fn exact_due_filter_ignores_the_stored_time_test() {
  let morning = pending_due(2, "morning", "2026-07-24T00:00")
  let evening = pending_due(1, "evening", "2026-07-24T23:59")
  let later = pending_due(3, "later", "2026-07-25T00:00")

  tasks.visible_sorted(
    [morning, later, evening],
    resolved(ListFilter(PendingOnly, Some(Exact(today())))),
  )
  |> should.equal([evening, morning])
}

pub fn today_due_filter_excludes_tasks_without_a_due_date_test() {
  let undated = Todo(1, "undated", 0, 3, None, Pending)
  let due_today = pending_due(2, "today", "2026-07-24T12:00")

  tasks.visible_sorted(
    [undated, due_today],
    resolved(ListFilter(PendingOnly, Some(Today))),
  )
  |> should.equal([due_today])
}

pub fn overdue_is_strictly_before_today_test() {
  let overdue = pending_due(1, "overdue", "2026-07-23T23:59")
  let due_today = pending_due(2, "today", "2026-07-24T00:00")

  tasks.visible_sorted(
    [due_today, overdue],
    resolved(ListFilter(PendingOnly, Some(Overdue))),
  )
  |> should.equal([overdue])
}

pub fn due_range_includes_both_boundaries_test() {
  let start = pending_due(1, "start", "2026-07-24T23:59")
  let end = pending_due(2, "end", "2026-07-25T00:00")
  let outside = pending_due(3, "outside", "2026-07-26T00:00")
  let assert Ok(until) = due.parse_date("2026-07-25")

  tasks.visible_sorted(
    [outside, end, start],
    resolved(ListFilter(PendingOnly, Some(Range(Some(today()), Some(until))))),
  )
  |> should.equal([start, end])
}

pub fn one_sided_due_ranges_are_inclusive_test() {
  let before = pending_due(1, "before", "2026-07-23T00:00")
  let boundary = pending_due(2, "boundary", "2026-07-24T00:00")
  let after = pending_due(3, "after", "2026-07-25T00:00")

  tasks.visible_sorted(
    [after, boundary, before],
    resolved(ListFilter(PendingOnly, Some(Range(Some(today()), None)))),
  )
  |> should.equal([boundary, after])
  tasks.visible_sorted(
    [after, boundary, before],
    resolved(ListFilter(PendingOnly, Some(Range(None, Some(today()))))),
  )
  |> should.equal([before, boundary])
}

pub fn status_and_due_filters_are_combined_with_and_test() {
  let pending = pending_due(1, "pending", "2026-07-23T00:00")
  let completed = Todo(2, "done", 0, 3, Some(Due("2026-07-23T00:00")), Done)

  tasks.visible_sorted(
    [pending, completed],
    resolved(ListFilter(DoneOnly, Some(Overdue))),
  )
  |> should.equal([completed])
}

pub fn parse_date_requires_a_real_zero_padded_date_test() {
  due.parse_date("2026-07-24") |> should.equal(Ok(today()))
  ["2026-7-24", "2026-02-29", "0000-01-01", "2026-04-31"]
  |> list.each(fn(value) { due.parse_date(value) |> should.equal(Error(Nil)) })
}

pub fn completing_a_pending_task_preserves_the_other_tasks_test() {
  let selected = Todo(2, "selected", 0, 5, None, Pending)
  let other = Todo(1, "other", 0, 3, None, Pending)

  tasks.complete([selected, other], 2)
  |> should.equal(
    Ok(#(
      [Todo(2, "selected", 0, 5, None, Done), other],
      Todo(2, "selected", 0, 5, None, Done),
    )),
  )
}

pub fn a_completed_task_cannot_be_completed_again_test() {
  let completed = Todo(1, "done", 0, 3, None, Done)

  tasks.complete([completed], 1) |> should.equal(Error(AlreadyDone))
}

pub fn an_unknown_task_cannot_be_completed_test() {
  let task = Todo(1, "existing", 0, 3, None, Pending)

  tasks.complete([task], 2) |> should.equal(Error(NotFound))
}
