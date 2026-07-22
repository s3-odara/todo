import datebook/weekday.{Friday, Monday, Sunday}
import gleam/time/calendar.{Date, July}
import gleeunit/should
import tasks/domain/availability.{
  Availability, DateOverride, Interval, WeeklyAvailability,
}

fn delete_intervals(values, deletion) {
  let monday = Date(2026, July, 20)
  Availability([WeeklyAvailability(Monday, values)], [])
  |> availability.apply(availability.DeleteWeekly([Monday], deletion))
  |> availability.effective(monday)
}

pub fn touching_and_overlapping_intervals_are_merged_test() {
  let value =
    availability.empty()
    |> availability.apply(availability.AddWeekly([Monday], Interval(540, 600)))
    |> availability.apply(availability.AddWeekly([Monday], Interval(600, 660)))
    |> availability.apply(availability.AddWeekly([Monday], Interval(570, 720)))

  value
  |> should.equal(
    Availability([WeeklyAvailability(Monday, [Interval(540, 720)])], []),
  )
}

pub fn deletion_splits_and_can_span_multiple_intervals_test() {
  delete_intervals(
    [Interval(540, 600), Interval(660, 720), Interval(780, 840)],
    Interval(570, 810),
  )
  |> should.equal([Interval(540, 570), Interval(810, 840)])
}

pub fn deletion_handles_containment_edges_and_empty_result_test() {
  delete_intervals([Interval(540, 720)], Interval(600, 660))
  |> should.equal([Interval(540, 600), Interval(660, 720)])
  delete_intervals([Interval(540, 720)], Interval(540, 600))
  |> should.equal([Interval(600, 720)])
  delete_intervals([Interval(540, 720)], Interval(660, 720))
  |> should.equal([Interval(540, 660)])
  delete_intervals([Interval(540, 720)], Interval(0, 1440))
  |> should.equal([])
}

pub fn date_add_and_delete_copy_weekly_before_overriding_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.apply(availability.AddWeekly([Monday], Interval(540, 720)))
  let added =
    availability.apply(weekly, availability.AddDate(monday, Interval(780, 840)))
  availability.effective(added, monday)
  |> should.equal([Interval(540, 720), Interval(780, 840)])

  availability.apply(
    weekly,
    availability.DeleteDate(monday, Interval(600, 660)),
  )
  |> availability.effective(monday)
  |> should.equal([Interval(540, 600), Interval(660, 720)])
}

pub fn close_overrides_weekly_availability_with_no_hours_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.apply(availability.AddWeekly([Monday], Interval(540, 720)))

  let closed = availability.apply(weekly, availability.CloseDate(monday))

  availability.effective(closed, monday) |> should.equal([])
}

pub fn reset_restores_weekly_availability_after_close_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.apply(availability.AddWeekly([Monday], Interval(540, 720)))
  let closed = availability.apply(weekly, availability.CloseDate(monday))

  let reset = availability.apply(closed, availability.ResetDate(monday))

  availability.effective(reset, monday) |> should.equal([Interval(540, 720)])
}

pub fn reset_without_an_override_leaves_availability_unchanged_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.apply(availability.AddWeekly([Monday], Interval(540, 720)))

  availability.apply(weekly, availability.ResetDate(monday))
  |> should.equal(weekly)
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
  availability.parse_days("mon,fri,sun")
  |> should.equal(Ok([Monday, Friday, Sunday]))
  let assert Error(_) = availability.parse_days("mon,mon")
  let assert Error(_) = availability.parse_days("mon,wat")
  let assert Error(_) = availability.parse_days("mon,")
}

pub fn empty_override_takes_precedence_over_weekly_test() {
  let monday = Date(2026, July, 20)
  Availability([WeeklyAvailability(Monday, [Interval(540, 720)])], [
    DateOverride(monday, []),
  ])
  |> availability.effective(monday)
  |> should.equal([])
}
