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

pub fn matches(filter: ListFilter, task: Todo, today: calendar.Date) -> Bool {
  let ListFilter(status, due_filter) = filter
  status_matches(status, task) && due_matches(due_filter, task, today)
}

fn status_matches(filter: StatusFilter, task: Todo) -> Bool {
  case filter {
    PendingOnly -> task.status == Pending
    DoneOnly -> task.status == Done
    AllStatuses -> True
  }
}

fn due_matches(
  filter: Option(DueFilter),
  task: Todo,
  today: calendar.Date,
) -> Bool {
  case filter, task.due {
    None, _ -> True
    Some(_), None -> False
    Some(filter), Some(stored) -> date_matches(due.date(stored), filter, today)
  }
}

fn date_matches(
  date: calendar.Date,
  filter: DueFilter,
  today: calendar.Date,
) -> Bool {
  case filter {
    Exact(wanted) -> calendar.naive_date_compare(date, wanted) == Eq
    Today -> calendar.naive_date_compare(date, today) == Eq
    Overdue -> calendar.naive_date_compare(date, today) == Lt
    Range(since, until) ->
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
