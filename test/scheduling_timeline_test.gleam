import gleam/list
import gleam/time/calendar
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/availability
import tasks/domain/scheduling/model.{ScheduleBlock}
import tasks/domain/scheduling/timeline.{AbsoluteInterval}

fn block(task_id, start, end) {
  ScheduleBlock(task_id, start, end)
}

fn unix_seconds(date, hour, minute) {
  timestamp.from_calendar(
    date,
    calendar.TimeOfDay(hour, minute, 0, 0),
    calendar.utc_offset,
  )
  |> timestamp.to_unix_seconds_and_nanoseconds
  |> fn(value) { value.0 }
}

fn thursday_with(intervals) {
  availability.Availability(
    [availability.WeeklyAvailability(availability.Thu, intervals)],
    [],
  )
}

pub fn canonical_free_intervals_are_carved_in_one_pass_test() {
  timeline.free_intervals([AbsoluteInterval(0, 100)], [])
  |> should.equal([AbsoluteInterval(0, 100)])
  timeline.free_intervals([AbsoluteInterval(0, 100)], [
    block(1, 0, 20),
    block(2, 40, 60),
    block(3, 80, 100),
  ])
  |> should.equal([AbsoluteInterval(20, 40), AbsoluteInterval(60, 80)])
  timeline.free_intervals([AbsoluteInterval(0, 20), AbsoluteInterval(40, 100)], [
    block(1, 0, 20),
    block(2, 50, 70),
  ])
  |> should.equal([AbsoluteInterval(40, 50), AbsoluteInterval(70, 100)])
}

pub fn empty_or_fully_occupied_timeline_has_no_free_intervals_test() {
  timeline.free_intervals([], []) |> should.equal([])
  timeline.free_intervals([AbsoluteInterval(-120, -60)], [block(1, -120, -60)])
  |> should.equal([])
}

pub fn projection_clips_discards_and_merges_raw_intervals_test() {
  let value =
    thursday_with([
      availability.Interval(0, 30),
      availability.Interval(30, 60),
      availability.Interval(60, 120),
    ])

  timeline.project(value, 30 * 60, 90 * 60, 0)
  |> should.equal(Ok([AbsoluteInterval(30 * 60, 90 * 60)]))
  timeline.project(value, 60 * 60, 60 * 60, 0)
  |> should.equal(Ok([]))
}

pub fn projection_limit_counts_raw_clipped_additions_before_merge_test() {
  let interval = availability.Interval(0, 1)
  let at_limit = thursday_with(list.repeat(interval, 10_000))
  let over_limit = thursday_with(list.repeat(interval, 10_001))

  timeline.project(at_limit, 0, 60, 0)
  |> should.equal(Ok([AbsoluteInterval(0, 60)]))
  timeline.project(over_limit, 0, 60, 0)
  |> should.equal(Error(timeline.SearchSpaceTooLarge))
}

pub fn final_date_finishes_without_requesting_a_following_date_test() {
  // Year zero is representable by Timestamp, but rejected by domain next_date.
  // A horizon wholly on that final date therefore succeeds only if no next date
  // is requested after processing it.
  let final_date = calendar.Date(0, calendar.December, 31)
  let lower = unix_seconds(final_date, 0, 0)

  timeline.project(availability.empty(), lower, lower + 60, 0)
  |> should.equal(Ok([]))
}

pub fn calendar_failure_before_the_last_date_is_mapped_test() {
  let invalid_domain_date = calendar.Date(0, calendar.December, 31)
  let first = unix_seconds(invalid_domain_date, 0, 0)
  let following = unix_seconds(calendar.Date(1, calendar.January, 1), 0, 1)

  timeline.project(availability.empty(), first, following, 0)
  |> should.equal(Error(timeline.InvalidCalendarRange))
}
