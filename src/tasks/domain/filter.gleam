import gleam/option.{type Option, None, Some}
import gleam/order.{Lt}
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/due.{type Due}
import tasks/domain/model.{type Status, Done, Pending}

pub type StatusFilter {
  PendingOnly
  DoneOnly
  AllStatuses
}

/// A calendar-relative time selection shared by task and schedule lists.
pub type TimeFilter {
  AnyTime
  Today
  On(calendar.Date)
  Overdue
  DateRange(since: Option(calendar.Date), until: Option(calendar.Date))
}

/// An absolute half-open window after runtime-relative inputs are frozen.
pub type TimeWindow {
  Unbounded
  Window(since: Option(Timestamp), until: Option(Timestamp))
}

pub fn resolve(
  filter: TimeFilter,
  now: Timestamp,
  offset: Duration,
) -> TimeWindow {
  case filter {
    AnyTime -> Unbounded
    On(date) -> day_window(date, offset)
    Today -> {
      let #(date, _) = timestamp.to_calendar(now, offset)
      day_window(date, offset)
    }
    Overdue -> Window(None, Some(now))
    DateRange(since, until) ->
      Window(
        option.map(since, fn(date) { start_of_day(date, offset) }),
        option.map(until, fn(date) { end_of_day_exclusive(date, offset) }),
      )
  }
}

pub fn task_matches(
  wanted_status: StatusFilter,
  window: TimeWindow,
  status: Status,
  stored: Option(Due),
) -> Bool {
  status_matches(wanted_status, status) && due_matches(window, stored)
}

pub fn status_matches(filter: StatusFilter, status: Status) -> Bool {
  case filter {
    PendingOnly -> status == Pending
    DoneOnly -> status == Done
    AllStatuses -> True
  }
}

/// Scheduled blocks overlap a local-day window rather than merely starting in it.
pub fn block_overlaps(
  start_seconds: Int,
  end_seconds: Int,
  window: TimeWindow,
) -> Bool {
  case window {
    Unbounded -> True
    Window(since, until) -> {
      let after_start = case since {
        None -> True
        Some(value) -> end_seconds > unix_seconds(value)
      }
      let before_end = case until {
        None -> True
        Some(value) -> start_seconds < unix_seconds(value)
      }
      after_start && before_end
    }
  }
}

fn unix_seconds(value: Timestamp) -> Int {
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(value)
  seconds
}

fn due_matches(window: TimeWindow, stored: Option(Due)) -> Bool {
  case window, stored {
    Unbounded, _ -> True
    Window(_, _), None -> False
    Window(since, until), Some(value) -> {
      let instant = due.instant(value)
      within_lower_bound(instant, since) && within_upper_bound(instant, until)
    }
  }
}

fn within_lower_bound(instant: Timestamp, since: Option(Timestamp)) -> Bool {
  case since {
    None -> True
    Some(start) -> timestamp.compare(instant, start) != Lt
  }
}

fn within_upper_bound(instant: Timestamp, until: Option(Timestamp)) -> Bool {
  case until {
    None -> True
    Some(end) -> timestamp.compare(instant, end) == Lt
  }
}

fn day_window(date: calendar.Date, offset: Duration) -> TimeWindow {
  Window(
    Some(start_of_day(date, offset)),
    Some(end_of_day_exclusive(date, offset)),
  )
}

fn start_of_day(date: calendar.Date, offset: Duration) -> Timestamp {
  timestamp.from_calendar(date, calendar.TimeOfDay(0, 0, 0, 0), offset)
}

fn end_of_day_exclusive(date: calendar.Date, offset: Duration) -> Timestamp {
  start_of_day(date, offset)
  |> timestamp.add(duration.hours(24))
}
