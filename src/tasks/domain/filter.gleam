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

pub type DueFilter {
  Exact(calendar.Date)
  Today
  Overdue
  Range(since: Option(calendar.Date), until: Option(calendar.Date))
}

pub type ListFilter {
  ListFilter(status: StatusFilter, due: Option(DueFilter))
}

pub type ScheduledExact {
  ScheduledToday
  ScheduledDate(calendar.Date)
}

pub type ScheduledFilter {
  AllScheduled
  ScheduledExact(ScheduledExact)
  ScheduledRange(since: Option(calendar.Date), until: Option(calendar.Date))
}

/// A scheduled filter after runtime-relative inputs have been frozen.
pub type ResolvedScheduledFilter {
  ResolvedAllScheduled
  ResolvedScheduledDate(calendar.Date)
  ResolvedScheduledToday(Timestamp)
  ResolvedScheduledRange(
    since: Option(calendar.Date),
    until: Option(calendar.Date),
  )
}

pub type ListQuery {
  TaskList(ListFilter)
  ScheduledList(status: StatusFilter, filter: ScheduledFilter)
}

pub type ResolvedDueFilter {
  DueWindow(since: Option(Timestamp), until: Option(Timestamp))
}

pub type ResolvedListFilter {
  ResolvedListFilter(status: StatusFilter, due: Option(ResolvedDueFilter))
}

/// Freeze relative task-list calendar criteria into absolute timestamp windows once.
pub fn resolve(
  filter: ListFilter,
  now: Timestamp,
  offset: Duration,
) -> ResolvedListFilter {
  let ListFilter(status, due_filter) = filter
  let #(today, _) = timestamp.to_calendar(now, offset)
  let resolved_due = case due_filter {
    None -> None
    Some(Exact(date)) -> Some(day_window(date, offset))
    Some(Today) -> Some(day_window(today, offset))
    Some(Overdue) -> Some(DueWindow(None, Some(now)))
    Some(Range(since, until)) ->
      Some(DueWindow(
        option.map(since, fn(date) { start_of_day(date, offset) }),
        option.map(until, fn(date) { end_of_day_exclusive(date, offset) }),
      ))
  }
  ResolvedListFilter(status, resolved_due)
}

pub fn matches(
  filter: ResolvedListFilter,
  status: Status,
  stored: Option(Due),
) -> Bool {
  let ResolvedListFilter(wanted_status, due_filter) = filter
  status_matches(wanted_status, status) && due_matches(due_filter, stored)
}

pub fn status_matches(filter: StatusFilter, status: Status) -> Bool {
  case filter {
    PendingOnly -> status == Pending
    DoneOnly -> status == Done
    AllStatuses -> True
  }
}

pub fn scheduled_window(
  filter: ResolvedScheduledFilter,
  offset: Duration,
) -> Option(ResolvedDueFilter) {
  case filter {
    ResolvedAllScheduled -> None
    ResolvedScheduledDate(date) -> Some(day_window(date, offset))
    ResolvedScheduledToday(current) -> {
      let #(date, _) = timestamp.to_calendar(current, offset)
      Some(day_window(date, offset))
    }
    ResolvedScheduledRange(since, until) ->
      Some(DueWindow(
        option.map(since, fn(date) { start_of_day(date, offset) }),
        option.map(until, fn(date) { end_of_day_exclusive(date, offset) }),
      ))
  }
}

/// Scheduled blocks overlap a local-day window rather than merely starting in it.
pub fn block_overlaps(
  start_seconds: Int,
  end_seconds: Int,
  window: Option(ResolvedDueFilter),
) -> Bool {
  case window {
    None -> True
    Some(DueWindow(since, until)) -> {
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

fn due_matches(filter: Option(ResolvedDueFilter), stored: Option(Due)) -> Bool {
  case filter, stored {
    None, _ -> True
    Some(_), None -> False
    Some(DueWindow(since, until)), Some(value) -> {
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

fn day_window(date: calendar.Date, offset: Duration) -> ResolvedDueFilter {
  DueWindow(
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
