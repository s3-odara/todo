import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}

/// A task deadline as an absolute instant, distinct from other scheduled times.
pub opaque type Due {
  Due(Timestamp)
}

// CLI input is a local calendar value. Date-only input means local end of day.
pub fn input(value: String, offset: Duration) -> Result(Due, Nil) {
  case string.length(value) {
    10 -> {
      use date <- result.try(parse_date(value))
      Ok(
        Due(timestamp.from_calendar(
          date,
          calendar.TimeOfDay(23, 59, 0, 0),
          offset,
        )),
      )
    }
    16 -> parse_datetime(value, offset)
    _ -> Error(Nil)
  }
}

/// Parse an RFC 3339 full-date with an exact, zero-padded Gregorian shape.
pub fn parse_date(value: String) -> Result(calendar.Date, Nil) {
  case date_shape(value) {
    False -> Error(Nil)
    True -> {
      use year <- result.try(slice_int(value, 0, 4))
      use month_number <- result.try(slice_int(value, 5, 2))
      use day <- result.try(slice_int(value, 8, 2))
      use month <- result.try(calendar.month_from_int(month_number))
      let date = calendar.Date(year, month, day)
      case year >= 1 && calendar.is_valid_date(date) {
        True -> Ok(date)
        False -> Error(Nil)
      }
    }
  }
}

/// Present a stored instant as the local minute at the supplied offset.
pub fn format(value: Due, offset: Duration) -> String {
  let #(date, time) = timestamp.to_calendar(instant(value), offset)
  [
    pad(date.year, 4),
    "-",
    pad(calendar.month_to_int(date.month), 2),
    "-",
    pad(date.day, 2),
    "T",
    pad(time.hours, 2),
    ":",
    pad(time.minutes, 2),
  ]
  |> string.concat
}

/// Deliberately unwrap a deadline when an absolute-time API is required.
pub fn instant(value: Due) -> Timestamp {
  let Due(value) = value
  value
}

pub fn from_unix_seconds(seconds: Int) -> Due {
  Due(timestamp.from_unix_seconds(seconds))
}

pub fn to_unix_seconds(value: Due) -> Int {
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(instant(value))
  seconds
}

fn parse_datetime(value: String, offset: Duration) -> Result(Due, Nil) {
  case datetime_shape(value) {
    False -> Error(Nil)
    True -> {
      use date <- result.try(parse_date(string.slice(value, 0, 10)))
      use hour <- result.try(slice_int(value, 11, 2))
      use minute <- result.try(slice_int(value, 14, 2))
      let time = calendar.TimeOfDay(hour, minute, 0, 0)
      case calendar.is_valid_time_of_day(time) {
        True -> Ok(Due(timestamp.from_calendar(date, time, offset)))
        False -> Error(Nil)
      }
    }
  }
}

fn date_shape(value: String) -> Bool {
  case string.to_graphemes(value) {
    [a, b, c, d, "-", e, f, "-", g, h] -> digits([a, b, c, d, e, f, g, h])
    _ -> False
  }
}

fn datetime_shape(value: String) -> Bool {
  case string.to_graphemes(value) {
    [a, b, c, d, "-", e, f, "-", g, h, "T", i, j, ":", k, l] ->
      digits([a, b, c, d, e, f, g, h, i, j, k, l])
    _ -> False
  }
}

fn digits(values: List(String)) -> Bool {
  list.all(values, fn(value) {
    list.contains(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"], value)
  })
}

fn slice_int(s: String, start: Int, length: Int) -> Result(Int, Nil) {
  string.slice(s, start, length) |> int.parse
}

fn pad(value: Int, width: Int) -> String {
  value |> int.to_string |> string.pad_start(width, "0")
}
