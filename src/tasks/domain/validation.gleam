import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tasks/domain/due
import tasks/domain/model.{type Due, type ValidatedAdd, ValidatedAdd}

pub fn add(
  raw_title: String,
  raw_estimate: String,
  raw_priority: String,
  raw_due: Option(String),
) -> Result(ValidatedAdd, Nil) {
  case
    title(raw_title),
    estimate(raw_estimate),
    priority(raw_priority),
    optional_due(raw_due)
  {
    Ok(clean), Ok(minutes), Ok(rank), Ok(due_value) ->
      Ok(ValidatedAdd(clean, minutes, rank, due_value))
    _, _, _, _ -> Error(Nil)
  }
}

pub fn done(raw_id: String) -> Result(Int, Nil) {
  id(raw_id)
}

fn title(value: String) -> Result(String, Nil) {
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
    False -> Error(Nil)
  }
}

fn id(value: String) -> Result(Int, Nil) {
  case strict_number(value) {
    Ok(n) if n > 0 -> Ok(n)
    _ -> Error(Nil)
  }
}

fn priority(value: String) -> Result(Int, Nil) {
  number_between(value, 1, 5)
}

fn estimate(value: String) -> Result(Int, Nil) {
  // Split the final ASCII unit, not the first grapheme: durations may have
  // more than one digit.
  case list.reverse(string.to_graphemes(value)) {
    [unit, ..reversed_number] -> {
      let number = string.concat(list.reverse(reversed_number))
      case unit {
        "m" -> number_between(number, 0, 525_600)
        "h" ->
          number_between(number, 0, 8760)
          |> result.map(fn(hours) { hours * 60 })
        _ -> Error(Nil)
      }
    }
    [] -> Error(Nil)
  }
}

fn optional_due(raw: Option(String)) -> Result(Option(Due), Nil) {
  case raw {
    None -> Ok(None)
    Some(value) -> due.input(value) |> result.map(Some)
  }
}

fn number_between(
  value: String,
  minimum: Int,
  maximum: Int,
) -> Result(Int, Nil) {
  case strict_number(value) {
    Ok(number) if number >= minimum && number <= maximum -> Ok(number)
    _ -> Error(Nil)
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
