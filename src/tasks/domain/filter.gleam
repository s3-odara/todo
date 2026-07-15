import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/due.{type Due}
import tasks/domain/model.{type Todo, Done, Pending}

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

pub type ResolvedDueFilter {
  On(calendar.Date)
  Before(Timestamp)
  Within(since: Option(calendar.Date), until: Option(calendar.Date))
}

pub type ResolvedListFilter {
  ResolvedListFilter(
    status: StatusFilter,
    due: Option(ResolvedDueFilter),
    offset: Duration,
  )
}

/// Freeze the clock and local offset once; matching below remains pure.
pub fn resolve(
  filter: ListFilter,
  now: Timestamp,
  offset: Duration,
) -> ResolvedListFilter {
  let ListFilter(status, due_filter) = filter
  let #(today, _) = timestamp.to_calendar(now, offset)
  let resolved_due = case due_filter {
    None -> None
    Some(Exact(date)) -> Some(On(date))
    Some(Today) -> Some(On(today))
    Some(Overdue) -> Some(Before(now))
    Some(Range(since, until)) -> Some(Within(since, until))
  }
  ResolvedListFilter(status, resolved_due, offset)
}

pub fn matches(filter: ResolvedListFilter, task: Todo) -> Bool {
  let ResolvedListFilter(status, due_filter, offset) = filter
  status_matches(status, task) && due_matches(due_filter, task.due, offset)
}

fn status_matches(filter: StatusFilter, task: Todo) -> Bool {
  case filter {
    PendingOnly -> task.status == Pending
    DoneOnly -> task.status == Done
    AllStatuses -> True
  }
}

fn due_matches(
  filter: Option(ResolvedDueFilter),
  stored: Option(Due),
  offset: Duration,
) -> Bool {
  case filter, stored {
    None, _ -> True
    Some(_), None -> False
    Some(Before(now)), Some(value) -> due.is_before(value, now)
    Some(filter), Some(value) ->
      date_matches(due.local_date(value, offset), filter)
  }
}

fn date_matches(date: calendar.Date, filter: ResolvedDueFilter) -> Bool {
  case filter {
    On(wanted) -> calendar.naive_date_compare(date, wanted) == Eq
    Within(since, until) ->
      within_lower_bound(date, since) && within_upper_bound(date, until)
    // Handled before calendar conversion so overdue compares exact instants.
    Before(_) -> False
  }
}

fn within_lower_bound(
  date: calendar.Date,
  since: Option(calendar.Date),
) -> Bool {
  case since {
    None -> True
    Some(start) -> calendar.naive_date_compare(date, start) != Lt
  }
}

fn within_upper_bound(
  date: calendar.Date,
  until: Option(calendar.Date),
) -> Bool {
  case until {
    None -> True
    Some(end) -> calendar.naive_date_compare(date, end) != Gt
  }
}
