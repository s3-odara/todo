import gleam/option.{type Option}
import gleam/time/calendar

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
