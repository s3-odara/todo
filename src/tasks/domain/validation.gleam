import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tasks/domain/due
import tasks/domain/model.{
  type AddRequest, type DoneRequest, type Due, type Error, type ValidatedAdd,
  AddRequest, DoneRequest, InvalidInput, ValidatedAdd,
}

pub fn add(request: AddRequest) -> Result(ValidatedAdd, Error) {
  let AddRequest(raw_title, raw_estimate, raw_priority, raw_due) = request
  case
    title(raw_title),
    estimate(raw_estimate),
    priority(raw_priority),
    optional_due(raw_due)
  {
    Ok(clean), Ok(minutes), Ok(rank), Ok(due_value) ->
      Ok(ValidatedAdd(clean, minutes, rank, due_value))
    _, _, _, _ -> Error(InvalidInput)
  }
}

pub fn done(request: DoneRequest) -> Result(Int, Error) {
  let DoneRequest(raw_id) = request
  id(raw_id)
}

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

fn optional_due(raw: Option(String)) -> Result(Option(Due), Error) {
  case raw {
    None -> Ok(None)
    Some(value) -> due.input(value) |> result.map(Some)
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
