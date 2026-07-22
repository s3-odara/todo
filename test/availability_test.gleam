import datebook/weekday.{Friday, Monday, Sunday}
import gleam/list
import gleam/time/calendar.{Date, July}
import gleeunit/should
import tasks/domain/availability.{
  Availability, DateOverride, Interval, WeeklyAvailability,
}

pub fn touching_and_overlapping_intervals_are_merged_test() {
  let value =
    availability.empty()
    |> availability.weekly_add([Monday], Interval(540, 600))
    |> availability.weekly_add([Monday], Interval(600, 660))
    |> availability.weekly_add([Monday], Interval(570, 720))

  value
  |> should.equal(
    Availability([WeeklyAvailability(Monday, [Interval(540, 720)])], []),
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
    |> availability.weekly_add([Monday], Interval(540, 720))
  let added = availability.date_add(weekly, monday, Interval(780, 840))
  availability.effective(added, monday)
  |> should.equal([Interval(540, 720), Interval(780, 840)])

  availability.date_delete(weekly, monday, Interval(600, 660))
  |> availability.effective(monday)
  |> should.equal([Interval(540, 600), Interval(660, 720)])
}

pub fn close_overrides_weekly_availability_with_no_hours_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.weekly_add([Monday], Interval(540, 720))

  let closed = availability.date_close(weekly, monday)

  availability.effective(closed, monday) |> should.equal([])
}

pub fn reset_restores_weekly_availability_after_close_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.weekly_add([Monday], Interval(540, 720))
  let closed = availability.date_close(weekly, monday)

  let reset = availability.date_reset(closed, monday)

  availability.effective(reset, monday) |> should.equal([Interval(540, 720)])
}

pub fn reset_without_an_override_leaves_availability_unchanged_test() {
  let monday = Date(2026, July, 20)
  let weekly =
    availability.empty()
    |> availability.weekly_add([Monday], Interval(540, 720))

  availability.date_reset(weekly, monday) |> should.equal(weekly)
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

pub fn aggregate_canonicality_is_a_domain_rule_test() {
  let canonical =
    Availability(
      [
        WeeklyAvailability(Monday, [Interval(540, 720)]),
        WeeklyAvailability(Friday, [Interval(780, 840)]),
      ],
      [DateOverride(Date(2026, July, 21), [])],
    )
  availability.is_canonical(canonical) |> should.be_true

  let Availability(weekly, overrides) = canonical
  availability.is_canonical(Availability(list.reverse(weekly), overrides))
  |> should.be_false
  availability.is_canonical(Availability(
    [WeeklyAvailability(Monday, [])],
    overrides,
  ))
  |> should.be_false
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
