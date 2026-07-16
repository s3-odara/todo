import gleam/time/calendar.{type Date}

pub type LocalMinute =
  Int

pub type Weekday {
  Mon
  Tue
  Wed
  Thu
  Fri
  Sat
  Sun
}

pub type Interval {
  Interval(from: LocalMinute, to: LocalMinute)
}

pub type WeeklyAvailability {
  WeeklyAvailability(day: Weekday, intervals: List(Interval))
}

pub type DateOverride {
  DateOverride(date: Date, intervals: List(Interval))
}

pub type Availability {
  Availability(weekly: List(WeeklyAvailability), overrides: List(DateOverride))
}

pub fn empty() -> Availability {
  Availability([], [])
}
