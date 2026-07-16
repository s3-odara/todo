import datebook/date
import datebook/weekday
import gleam/int
import gleam/string
import gleam/time/calendar.{type Date}

pub type Weekday {
  Mon
  Tue
  Wed
  Thu
  Fri
  Sat
  Sun
}

/// Format a date using the canonical representation shared by CLI and storage.
pub fn format_date(value: Date) -> String {
  [
    value.year |> int.to_string |> string.pad_start(4, "0"),
    value.month
      |> calendar.month_to_int
      |> int.to_string
      |> string.pad_start(2, "0"),
    value.day |> int.to_string |> string.pad_start(2, "0"),
  ]
  |> string.join("-")
}

/// Return the domain weekday for a valid Gregorian date.
pub fn weekday_for_date(value: Date) -> Result(Weekday, Nil) {
  case value.year >= 1 && calendar.is_valid_date(value) {
    False -> Error(Nil)
    True ->
      Ok(case weekday.from_date(value) {
        weekday.Monday -> Mon
        weekday.Tuesday -> Tue
        weekday.Wednesday -> Wed
        weekday.Thursday -> Thu
        weekday.Friday -> Fri
        weekday.Saturday -> Sat
        weekday.Sunday -> Sun
      })
  }
}

/// Advance one Gregorian day. Year 1 and year boundaries are supported.
pub fn next_date(value: Date) -> Result(Date, Nil) {
  case value.year >= 1 && calendar.is_valid_date(value) {
    False -> Error(Nil)
    True -> Ok(date.next(value))
  }
}
