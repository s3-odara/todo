import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import tasks/domain/model.{type Due, Due}

// CLI input accepts date-only as end of day.
pub fn input(value: String) -> Result(Due, Nil) {
  case string.length(value) {
    10 ->
      parse_date(value)
      |> result_to_due(value <> "T23:59")
    16 -> validate_datetime(value)
    _ -> Error(Nil)
  }
}

/// Parse an exact, zero-padded Gregorian calendar date.
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

fn result_to_due(
  result: Result(calendar.Date, Nil),
  canonical: String,
) -> Result(Due, Nil) {
  case result {
    Ok(_) -> Ok(Due(canonical))
    Error(error) -> Error(error)
  }
}

fn validate_datetime(value: String) -> Result(Due, Nil) {
  case datetime_shape(value), parse_date(string.slice(value, 0, 10)) {
    True, Ok(_) -> {
      let hour = slice_int(value, 11, 2)
      let minute = slice_int(value, 14, 2)
      case hour, minute {
        Ok(hour), Ok(minute) if hour <= 23 && minute <= 59 -> Ok(Due(value))
        _, _ -> Error(Nil)
      }
    }
    _, _ -> Error(Nil)
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
