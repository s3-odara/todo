import datebook/weekday.{
  type Weekday, Friday, Monday, Saturday, Sunday, Thursday, Tuesday, Wednesday,
}
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar.{type Date}
import tasks/domain/ascii

pub type LocalMinute =
  Int

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

pub type Mutation {
  AddWeekly(days: List(Weekday), interval: Interval)
  DeleteWeekly(days: List(Weekday), interval: Interval)
  SetDate(date: Date, interval: Interval)
  AddDate(date: Date, interval: Interval)
  DeleteDate(date: Date, interval: Interval)
  CloseDate(date: Date)
  ResetDate(date: Date)
}

pub fn empty() -> Availability {
  Availability([], [])
}

fn parse_minute(
  value: String,
  allow_end_of_day: Bool,
) -> Result(LocalMinute, Nil) {
  case string.to_graphemes(value) {
    [a, b, ":", c, d] -> {
      use hour <- result.try(ascii.parse_digits([a, b]))
      use minute <- result.try(ascii.parse_digits([c, d]))
      case hour, minute, allow_end_of_day {
        24, 0, True -> Ok(1440)
        hour, minute, _
          if hour >= 0 && hour < 24 && minute >= 0 && minute < 60
        -> Ok(hour * 60 + minute)
        _, _, _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

pub fn parse_interval(from: String, to: String) -> Result(Interval, Nil) {
  use from <- result.try(parse_minute(from, False))
  use to <- result.try(parse_minute(to, True))
  case from < to {
    True -> Ok(Interval(from, to))
    False -> Error(Nil)
  }
}

pub fn parse_days(value: String) -> Result(List(Weekday), Nil) {
  use days <- result.try(
    value
    |> string.split(",")
    |> list.try_map(parse_day),
  )
  case days != [] && days == list.unique(days) {
    True -> Ok(days)
    False -> Error(Nil)
  }
}

pub fn parse_day(value: String) -> Result(Weekday, Nil) {
  case value {
    "mon" -> Ok(Monday)
    "tue" -> Ok(Tuesday)
    "wed" -> Ok(Wednesday)
    "thu" -> Ok(Thursday)
    "fri" -> Ok(Friday)
    "sat" -> Ok(Saturday)
    "sun" -> Ok(Sunday)
    _ -> Error(Nil)
  }
}

fn add_intervals(values: List(Interval), addition: Interval) -> List(Interval) {
  canonicalize([addition, ..values])
}

pub fn delete_intervals(
  values: List(Interval),
  deletion: Interval,
) -> List(Interval) {
  values
  |> list.flat_map(fn(value) { subtract(value, deletion) })
  |> canonicalize
}

pub fn canonicalize(values: List(Interval)) -> List(Interval) {
  values
  |> list.sort(by: interval_compare)
  |> merge_sorted([])
  |> list.reverse
}

pub fn intervals_are_canonical(values: List(Interval)) -> Bool {
  values == canonicalize(values) && list.all(values, valid_interval)
}

/// Validate the aggregate shape maintained by availability mutations.
/// Persistence rejects noncanonical input rather than silently normalizing it.
pub fn is_canonical(value: Availability) -> Bool {
  let Availability(weekly, overrides) = value
  all_unique_by(weekly, fn(entry) { entry.day })
  && all_unique_by(overrides, fn(entry) { entry.date })
  && weekly == sort_weekly(weekly)
  && overrides == sort_overrides(overrides)
  && list.all(weekly, fn(entry) {
    entry.intervals != [] && intervals_are_canonical(entry.intervals)
  })
  && list.all(overrides, fn(entry) { intervals_are_canonical(entry.intervals) })
}

pub fn weekly_add(
  value: Availability,
  days: List(Weekday),
  interval: Interval,
) -> Availability {
  update_weekly(value, days, fn(intervals) {
    add_intervals(intervals, interval)
  })
}

fn weekly_delete(
  value: Availability,
  days: List(Weekday),
  interval: Interval,
) -> Availability {
  update_weekly(value, days, fn(intervals) {
    delete_intervals(intervals, interval)
  })
}

fn update_weekly(value, days, update) {
  let Availability(weekly, overrides) = value
  Availability(
    days
      |> list.fold(weekly, fn(entries, day) {
        put_weekly(entries, day, update(weekly_for(entries, day)))
      })
      |> sort_weekly,
    overrides,
  )
}

fn date_set(
  value: Availability,
  date: Date,
  interval: Interval,
) -> Availability {
  put_override(value, date, [interval])
}

pub fn date_add(
  value: Availability,
  date: Date,
  interval: Interval,
) -> Availability {
  put_override(value, date, add_intervals(effective(value, date), interval))
}

pub fn date_delete(
  value: Availability,
  date: Date,
  interval: Interval,
) -> Availability {
  put_override(value, date, delete_intervals(effective(value, date), interval))
}

pub fn date_close(value: Availability, date: Date) -> Availability {
  put_override(value, date, [])
}

pub fn date_reset(value: Availability, date: Date) -> Availability {
  let Availability(weekly, overrides) = value
  Availability(weekly, list.filter(overrides, fn(entry) { entry.date != date }))
}

pub fn effective(value: Availability, date: Date) -> List(Interval) {
  let Availability(weekly, overrides) = value
  case find_override(overrides, date) {
    Ok(intervals) -> intervals
    // CLI and JSON inputs are validated before they reach the domain state.
    Error(_) -> weekly_for(weekly, weekday.from_date(date))
  }
}

pub fn apply(value: Availability, mutation: Mutation) -> Availability {
  case mutation {
    AddWeekly(days, interval) -> weekly_add(value, days, interval)
    DeleteWeekly(days, interval) -> weekly_delete(value, days, interval)
    SetDate(date, interval) -> date_set(value, date, interval)
    AddDate(date, interval) -> date_add(value, date, interval)
    DeleteDate(date, interval) -> date_delete(value, date, interval)
    CloseDate(date) -> date_close(value, date)
    ResetDate(date) -> date_reset(value, date)
  }
}

pub fn weekday_number(day: Weekday) -> Int {
  weekday.days_since(day, Monday) + 1
}

pub fn weekday_string(day: Weekday) -> String {
  case day {
    Monday -> "mon"
    Tuesday -> "tue"
    Wednesday -> "wed"
    Thursday -> "thu"
    Friday -> "fri"
    Saturday -> "sat"
    Sunday -> "sun"
  }
}

fn valid_interval(value: Interval) -> Bool {
  value.from >= 0 && value.from < value.to && value.to <= 1440
}

fn interval_compare(a: Interval, b: Interval) -> order.Order {
  case int.compare(a.from, b.from) {
    order.Eq -> int.compare(a.to, b.to)
    other -> other
  }
}

fn merge_sorted(values: List(Interval), acc: List(Interval)) -> List(Interval) {
  case values, acc {
    [], _ -> acc
    [next, ..rest], [] -> merge_sorted(rest, [next])
    [next, ..rest], [current, ..previous] ->
      case next.from <= current.to {
        True ->
          merge_sorted(rest, [
            Interval(current.from, int.max(current.to, next.to)),
            ..previous
          ])
        False -> merge_sorted(rest, [next, current, ..previous])
      }
  }
}

fn subtract(value: Interval, deletion: Interval) -> List(Interval) {
  case deletion.to <= value.from || deletion.from >= value.to {
    True -> [value]
    False -> {
      let left = case deletion.from > value.from {
        True -> [Interval(value.from, int.min(deletion.from, value.to))]
        False -> []
      }
      let right = case deletion.to < value.to {
        True -> [Interval(int.max(deletion.to, value.from), value.to)]
        False -> []
      }
      list.append(left, right)
    }
  }
}

fn weekly_for(
  entries: List(WeeklyAvailability),
  day: Weekday,
) -> List(Interval) {
  case entries {
    [] -> []
    [WeeklyAvailability(entry_day, intervals), ..rest] ->
      case entry_day == day {
        True -> intervals
        False -> weekly_for(rest, day)
      }
  }
}

fn put_weekly(
  entries: List(WeeklyAvailability),
  day: Weekday,
  intervals: List(Interval),
) -> List(WeeklyAvailability) {
  let without = list.filter(entries, fn(entry) { entry.day != day })
  case intervals {
    [] -> without
    _ -> [WeeklyAvailability(day, intervals), ..without]
  }
}

fn sort_weekly(entries: List(WeeklyAvailability)) -> List(WeeklyAvailability) {
  list.sort(entries, by: fn(a, b) {
    int.compare(weekday_number(a.day), weekday_number(b.day))
  })
}

fn sort_overrides(entries: List(DateOverride)) -> List(DateOverride) {
  list.sort(entries, by: fn(a, b) {
    calendar.naive_date_compare(a.date, b.date)
  })
}

fn all_unique_by(values: List(value), key: fn(value) -> key) -> Bool {
  let keys = list.map(values, key)
  keys == list.unique(keys)
}

fn find_override(
  entries: List(DateOverride),
  date: Date,
) -> Result(List(Interval), Nil) {
  case entries {
    [] -> Error(Nil)
    [DateOverride(entry_date, intervals), ..rest] ->
      case entry_date == date {
        True -> Ok(intervals)
        False -> find_override(rest, date)
      }
  }
}

fn put_override(value, date, intervals) {
  let Availability(weekly, overrides) = value
  let without = list.filter(overrides, fn(entry) { entry.date != date })
  Availability(
    weekly,
    [DateOverride(date, canonicalize(intervals)), ..without]
      |> sort_overrides,
  )
}
