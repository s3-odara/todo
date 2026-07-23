import gleam/list
import gleam/order.{type Order}
import gleam/string
import youid/uuid.{type Uuid}

/// The constructor stays private so every task ID is a validated UUIDv7.
pub opaque type TaskId {
  TaskId(value: Uuid)
}

pub fn generate() -> TaskId {
  TaskId(uuid.v7())
}

pub fn parse(value: String) -> Result(TaskId, Nil) {
  case uuid.from_string(value) {
    Ok(id) ->
      case uuid.version(id) == uuid.V7 {
        True -> Ok(TaskId(id))
        False -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

pub fn to_string(id: TaskId) -> String {
  let TaskId(value) = id
  uuid.to_string(value)
}

pub fn compare(a: TaskId, b: TaskId) -> Order {
  string.compare(to_string(a), to_string(b))
}

/// Validate and normalize a CLI selector. UUIDv7 stores its timestamp at the
/// front, so short selectors use the random suffix rather than a shared prefix.
pub fn selector(value: String) -> Result(String, Nil) {
  let lowered = string.lowercase(value)
  case parse(lowered) {
    Ok(id) -> Ok(compact(id))
    Error(_) -> {
      let length = string.length(lowered)
      case
        !string.contains(lowered, "-")
        && length >= 8
        && length <= 32
        && is_hex(lowered)
      {
        True -> Ok(lowered)
        False -> Error(Nil)
      }
    }
  }
}

pub fn matches_selector(id: TaskId, normalized_selector: String) -> Bool {
  let value = compact(id)
  case string.length(normalized_selector) == 32 {
    True -> value == normalized_selector
    False -> string.ends_with(value, normalized_selector)
  }
}

pub fn short(id: TaskId) -> String {
  id |> compact |> string.drop_start(24)
}

fn compact(id: TaskId) -> String {
  id |> to_string |> string.replace("-", "")
}

fn is_hex(value: String) -> Bool {
  value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789abcdef", character) })
}
