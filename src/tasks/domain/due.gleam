import gleam/int
import gleam/list
import gleam/string
import tasks/domain/model.{type Due, type Error, Due, InvalidDue}

pub fn input(value: String) -> Result(Due, Error) {
  let canonical = case string.length(value) {
    10 -> value <> "T23:59"
    16 -> value
    _ -> ""
  }
  case valid_shape(canonical) && valid_date(canonical) {
    True -> Ok(Due(canonical))
    False -> Error(InvalidDue)
  }
}

pub fn persisted(value: String) -> Result(Due, Error) {
  case string.length(value) == 16 && valid_shape(value) && valid_date(value) {
    True -> Ok(Due(value))
    False -> Error(InvalidDue)
  }
}

fn valid_shape(s: String) -> Bool {
  let chars = string.to_graphemes(s)
  case chars {
    [a, b, c, d, "-", e, f, "-", g, h, "T", i, j, ":", k, l] ->
      digits([a, b, c, d, e, f, g, h, i, j, k, l])
    _ -> False
  }
}

fn digits(xs: List(String)) -> Bool {
  case xs {
    [] -> True
    [x, ..rest] ->
      list.contains(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"], x)
      && digits(rest)
  }
}

fn valid_date(s: String) -> Bool {
  let y = slice_int(s, 0, 4)
  let m = slice_int(s, 5, 2)
  let d = slice_int(s, 8, 2)
  let h = slice_int(s, 11, 2)
  let minute = slice_int(s, 14, 2)
  case y, m, d, h, minute {
    Ok(year), Ok(month), Ok(day), Ok(hour), Ok(min) ->
      year >= 1
      && month >= 1
      && month <= 12
      && day >= 1
      && day <= days(year, month)
      && hour <= 23
      && min <= 59
    _, _, _, _, _ -> False
  }
}

fn slice_int(s: String, start: Int, length: Int) -> Result(Int, Nil) {
  string.slice(s, start, length) |> int.parse
}

fn days(y: Int, m: Int) -> Int {
  case m {
    2 ->
      case leap(y) {
        True -> 29
        False -> 28
      }
    4 | 6 | 9 | 11 -> 30
    _ -> 31
  }
}

fn leap(y: Int) -> Bool {
  y % 400 == 0 || y % 4 == 0 && y % 100 != 0
}
