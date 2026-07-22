import datebook/weekday.{
  type Weekday, Friday, Monday, Saturday, Sunday, Thursday, Tuesday, Wednesday,
}
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar.{type Date}

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
      use hour <- result.try(int.parse(a <> b))
      use minute <- result.try(int.parse(c <> d))
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

type IntervalEdit {
  AddInterval(Interval)
  DeleteInterval(Interval)
  ReplaceIntervals(List(Interval))
}

fn edit_intervals(
  values: List(Interval),
  edit: IntervalEdit,
) -> List(Interval) {
  case edit {
    AddInterval(interval) -> canonicalize([interval, ..values])
    DeleteInterval(interval) ->
      values
      |> list.flat_map(fn(value) { subtract(value, interval) })
      |> canonicalize
    ReplaceIntervals(intervals) -> canonicalize(intervals)
  }
}

fn canonicalize(values: List(Interval)) -> List(Interval) {
  values
  |> list.sort(by: interval_compare)
  |> merge_sorted([])
  |> list.reverse
}

fn edit_weekly(value: Availability, days: List(Weekday), edit: IntervalEdit) {
  let Availability(weekly, overrides) = value
  Availability(
    days
      |> list.fold(weekly, fn(entries, day) {
        put_weekly(entries, day, edit_intervals(weekly_for(entries, day), edit))
      })
      |> sort_weekly,
    overrides,
  )
}

fn edit_date(value: Availability, date: Date, edit: IntervalEdit) {
  // Date edits snapshot effective weekly hours so later weekly changes do not
  // alter an existing override.
  put_override(value, date, edit_intervals(effective(value, date), edit))
}

fn reset_date(value: Availability, date: Date) -> Availability {
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
    AddWeekly(days, interval) -> edit_weekly(value, days, AddInterval(interval))
    DeleteWeekly(days, interval) ->
      edit_weekly(value, days, DeleteInterval(interval))
    SetDate(date, interval) ->
      edit_date(value, date, ReplaceIntervals([interval]))
    AddDate(date, interval) -> edit_date(value, date, AddInterval(interval))
    DeleteDate(date, interval) ->
      edit_date(value, date, DeleteInterval(interval))
    CloseDate(date) -> edit_date(value, date, ReplaceIntervals([]))
    ResetDate(date) -> reset_date(value, date)
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
  entries
  |> list.find(fn(entry) { entry.day == day })
  |> result.map(fn(entry) { entry.intervals })
  |> result.unwrap([])
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

fn find_override(
  entries: List(DateOverride),
  date: Date,
) -> Result(List(Interval), Nil) {
  entries
  |> list.find(fn(entry) { entry.date == date })
  |> result.map(fn(entry) { entry.intervals })
}

fn put_override(value, date, intervals) {
  let Availability(weekly, overrides) = value
  let without = list.filter(overrides, fn(entry) { entry.date != date })
  Availability(
    weekly,
    [DateOverride(date, intervals), ..without]
      |> sort_overrides,
  )
}
