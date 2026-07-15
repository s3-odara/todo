import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/time/calendar
import tasks/domain/due
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
  Before(calendar.Date)
  Within(since: Option(calendar.Date), until: Option(calendar.Date))
}

pub type ResolvedListFilter {
  ResolvedListFilter(status: StatusFilter, due: Option(ResolvedDueFilter))
}

/// Resolve relative CLI criteria once, before persistence and domain transforms.
pub fn resolve(filter: ListFilter, today: calendar.Date) -> ResolvedListFilter {
  let ListFilter(status, due_filter) = filter
  let resolved_due = case due_filter {
    None -> None
    Some(Exact(date)) -> Some(On(date))
    Some(Today) -> Some(On(today))
    Some(Overdue) -> Some(Before(today))
    Some(Range(since, until)) -> Some(Within(since, until))
  }
  ResolvedListFilter(status, resolved_due)
}

pub fn matches(filter: ResolvedListFilter, task: Todo) -> Bool {
  let ResolvedListFilter(status, due_filter) = filter
  status_matches(status, task) && due_matches(due_filter, task)
}

fn status_matches(filter: StatusFilter, task: Todo) -> Bool {
  case filter {
    PendingOnly -> task.status == Pending
    DoneOnly -> task.status == Done
    AllStatuses -> True
  }
}

fn due_matches(filter: Option(ResolvedDueFilter), task: Todo) -> Bool {
  case filter, task.due {
    None, _ -> True
    Some(_), None -> False
    Some(filter), Some(stored) -> date_matches(due.date(stored), filter)
  }
}

fn date_matches(date: calendar.Date, filter: ResolvedDueFilter) -> Bool {
  case filter {
    On(wanted) -> calendar.naive_date_compare(date, wanted) == Eq
    Before(boundary) -> calendar.naive_date_compare(date, boundary) == Lt
    Within(since, until) ->
      within_lower_bound(date, since) && within_upper_bound(date, until)
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
