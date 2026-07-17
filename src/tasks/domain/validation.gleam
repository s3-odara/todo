import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tasks/domain/ascii
import tasks/domain/due.{type Due}
import tasks/domain/model.{
  type Status, type Todo, type ValidatedAdd, Todo, ValidatedAdd,
}
import tasks/domain/policy.{type SchedulingPolicy, parse as parse_policy}

pub fn add(
  raw_title: String,
  raw_estimate: String,
  raw_priority: String,
  raw_due: Option(String),
  raw_policy: String,
  raw_minimum_split: String,
  due_parser: fn(String) -> Result(Due, Nil),
) -> Result(ValidatedAdd, Nil) {
  case
    title(raw_title),
    estimate(raw_estimate),
    priority(raw_priority),
    optional_due(raw_due, due_parser),
    parse_policy(raw_policy),
    positive_duration(raw_minimum_split)
  {
    Ok(clean), Ok(minutes), Ok(rank), Ok(due_value), Ok(policy), Ok(split) ->
      Ok(ValidatedAdd(clean, minutes, rank, due_value, policy, split))
    _, _, _, _, _, _ -> Error(Nil)
  }
}

pub fn persisted_task(
  id_value: Int,
  title_value: String,
  estimate_minutes: Int,
  priority_value: Int,
  due_value: Option(Due),
  status: Status,
  scheduling_policy: SchedulingPolicy,
  minimum_split_minutes: Int,
) -> Result(Todo, Nil) {
  case title(title_value) {
    Ok(clean)
      if clean == title_value
      && id_value > 0
      && estimate_minutes >= 0
      && estimate_minutes <= 525_600
      && priority_value >= 1
      && priority_value <= 5
      && minimum_split_minutes >= 1
      && minimum_split_minutes <= 525_600
    ->
      Ok(Todo(
        id_value,
        title_value,
        estimate_minutes,
        priority_value,
        due_value,
        status,
        scheduling_policy,
        minimum_split_minutes,
      ))
    _ -> Error(Nil)
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

fn optional_due(
  raw: Option(String),
  due_parser: fn(String) -> Result(Due, Nil),
) -> Result(Option(Due), Nil) {
  case raw {
    None -> Ok(None)
    Some(value) -> due_parser(value) |> result.map(Some)
  }
}

fn positive_duration(value: String) -> Result(Int, Nil) {
  case estimate(value) {
    Ok(minutes) if minutes > 0 -> Ok(minutes)
    _ -> Error(Nil)
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
    _ -> {
      let digits = string.to_graphemes(value)
      case string.starts_with(value, "0") || !ascii.digits(digits) {
        True -> Error(Nil)
        False -> ascii.parse_digits(digits)
      }
    }
  }
}
