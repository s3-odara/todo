import gleam/int
import gleam/string
import gleam/time/calendar.{type Date}
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}

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

/// Format a validated local minute; 1440 intentionally renders as 24:00.
pub fn format_minute_of_day(value: Int) -> String {
  format_clock(value / 60, value % 60)
}

/// Format an instant at minute precision using one fixed UTC offset.
pub fn format_timestamp(value: Timestamp, offset: Duration) -> String {
  let #(date, time) = timestamp.to_calendar(value, offset)
  format_date(date) <> "T" <> format_clock(time.hours, time.minutes)
}

fn format_clock(hour: Int, minute: Int) -> String {
  hour
  |> int.to_string
  |> string.pad_start(2, "0")
  |> string.append(":")
  |> string.append(minute |> int.to_string |> string.pad_start(2, "0"))
}

/// Mathematical modulo for time alignment before the Unix epoch.
pub fn floor_mod(value: Int, modulus: Int) -> Int {
  let raw = value % modulus
  case raw < 0 {
    True -> raw + modulus
    False -> raw
  }
}
