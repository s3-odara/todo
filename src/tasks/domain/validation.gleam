import gleam/int
import gleam/list
import gleam/string
import tasks/domain/model.{type Error, InvalidInput}

pub fn title(value: String) -> Result(String, Error) {
  // Check the supplied value before trimming: controls are never whitespace
  // that the CLI is permitted to silently normalise away.
  let clean = string.trim(value)
  let chars = string.to_utf_codepoints(clean)
  case
    list.length(chars) >= 1
    && list.length(chars) <= 200
    && !string.contains(value, "\t")
    && !string.contains(value, "\n")
    && !string.contains(value, "\r")
    && !string.contains(value, "\u{0}")
  {
    True -> Ok(clean)
    False -> Error(InvalidInput)
  }
}

pub fn id(value: String) -> Result(Int, Error) {
  case strict_number(value) {
    Ok(n) if n > 0 -> Ok(n)
    _ -> Error(InvalidInput)
  }
}

pub fn priority(value: String) -> Result(Int, Error) {
  case strict_number(value) {
    Ok(n) if n >= 1 && n <= 5 -> Ok(n)
    _ -> Error(InvalidInput)
  }
}

pub fn estimate(value: String) -> Result(Int, Error) {
  // Split the final ASCII unit, not the first grapheme: durations may have
  // more than one digit.
  case list.reverse(string.to_graphemes(value)) {
    [unit, ..reversed_number] ->
      case strict_number(string.concat(list.reverse(reversed_number))), unit {
        Ok(n), "m" if n <= 525_600 -> Ok(n)
        Ok(n), "h" if n <= 8760 -> Ok(n * 60)
        _, _ -> Error(InvalidInput)
      }
    [] -> Error(InvalidInput)
  }
}

fn strict_number(value: String) -> Result(Int, Nil) {
  case value {
    "0" -> Ok(0)
    _ ->
      case
        string.starts_with(value, "0")
        || value == ""
        || !list.all(string.to_graphemes(value), is_digit)
      {
        True -> Error(Nil)
        False -> int.parse(value)
      }
  }
}

fn is_digit(c: String) -> Bool {
  list.contains(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"], c)
}
