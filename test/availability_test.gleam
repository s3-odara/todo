import gleam/time/calendar.{Date, December, February, January, July}
import gleeunit/should
import tasks/domain/availability.{
  Availability, DateOverride, Fri, Interval, Mon, Sun, WeeklyAvailability,
}
import tasks/domain/local_time

pub fn touching_and_overlapping_intervals_are_merged_test() {
  let value =
    availability.empty()
    |> availability.weekly_add([Mon], Interval(540, 600))
    |> availability.weekly_add([Mon], Interval(600, 660))
    |> availability.weekly_add([Mon], Interval(570, 720))

  value
  |> should.equal(
    Availability([WeeklyAvailability(Mon, [Interval(540, 720)])], []),
  )
}

pub fn deletion_splits_and_can_span_multiple_intervals_test() {
  availability.delete_intervals(
    [Interval(540, 600), Interval(660, 720), Interval(780, 840)],
    Interval(570, 810),
  )
  |> should.equal([Interval(540, 570), Interval(810, 840)])
}

pub fn deletion_handles_containment_edges_and_empty_result_test() {
  availability.delete_intervals([Interval(540, 720)], Interval(600, 660))
  |> should.equal([Interval(540, 600), Interval(660, 720)])
  availability.delete_intervals([Interval(540, 720)], Interval(540, 600))
  |> should.equal([Interval(600, 720)])
  availability.delete_intervals([Interval(540, 720)], Interval(660, 720))
  |> should.equal([Interval(540, 660)])
  availability.delete_intervals([Interval(540, 720)], Interval(0, 1440))
  |> should.equal([])
}

pub fn date_add_and_delete_copy_weekly_before_overriding_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.weekly_add([Mon], Interval(540, 720))
  let added = availability.date_add(weekly, monday, Interval(780, 840))
  availability.effective(added, monday)
  |> should.equal([Interval(540, 720), Interval(780, 840)])

  availability.date_delete(weekly, monday, Interval(600, 660))
  |> availability.effective(monday)
  |> should.equal([Interval(540, 600), Interval(660, 720)])
}

pub fn close_and_reset_are_distinct_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.weekly_add([Mon], Interval(540, 720))
  let closed = availability.date_close(weekly, monday)
  availability.effective(closed, monday) |> should.equal([])
  let #(reset, changed) = availability.date_reset(closed, monday)
  changed |> should.be_true
  availability.effective(reset, monday) |> should.equal([Interval(540, 720)])
  let #(_, changed_again) = availability.date_reset(reset, monday)
  changed_again |> should.be_false
}

pub fn local_minute_parser_enforces_strict_boundaries_test() {
  availability.parse_interval("00:00", "24:00")
  |> should.equal(Ok(Interval(0, 1440)))
  let assert Error(_) = availability.parse_interval("24:00", "24:00")
  let assert Error(_) = availability.parse_interval("09:00", "09:00")
  let assert Error(_) = availability.parse_interval("10:00", "09:00")
  let assert Error(_) = availability.parse_interval("9:00", "10:00")
  let assert Error(_) = availability.parse_interval("０9:00", "10:00")
}

pub fn day_parser_rejects_duplicates_unknown_and_empty_parts_test() {
  availability.parse_days("mon,fri,sun") |> should.equal(Ok([Mon, Fri, Sun]))
  let assert Error(_) = availability.parse_days("mon,mon")
  let assert Error(_) = availability.parse_days("mon,wat")
  let assert Error(_) = availability.parse_days("mon,")
}

pub fn local_time_wrapper_handles_known_weekdays_and_date_boundaries_test() {
  local_time.weekday_for_date(Date(2026, July, 20))
  |> should.equal(Ok(local_time.Mon))
  local_time.weekday_for_date(Date(2026, July, 19))
  |> should.equal(Ok(local_time.Sun))
  local_time.weekday_for_date(Date(1969, December, 31))
  |> should.equal(Ok(local_time.Wed))
  local_time.next_date(Date(2024, February, 28))
  |> should.equal(Ok(Date(2024, February, 29)))
  local_time.next_date(Date(2026, December, 31))
  |> should.equal(Ok(Date(2027, January, 1)))
  local_time.next_date(Date(1, January, 1))
  |> should.equal(Ok(Date(1, January, 2)))
  let assert Error(_) = local_time.weekday_for_date(Date(0, January, 1))
  let assert Error(_) = local_time.next_date(Date(2026, February, 30))
}

pub fn empty_override_takes_precedence_over_weekly_test() {
  let monday = Date(2026, July, 20)
  Availability([WeeklyAvailability(Mon, [Interval(540, 720)])], [
    DateOverride(monday, []),
  ])
  |> availability.effective(monday)
  |> should.equal([])
}
