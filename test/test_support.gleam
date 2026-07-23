import gleam/int
import gleam/string
import tasks/domain/task_id.{type TaskId}

/// Stable UUID-shaped IDs keep fixtures readable while production IDs are
/// generated with UUIDv7 entropy at the application boundary.
pub fn id(number: Int) -> TaskId {
  let suffix = left_pad(int.to_string(number), 12)
  let assert Ok(value) = task_id.parse("00000000-0000-7000-8000-" <> suffix)
  value
}

fn left_pad(value: String, width: Int) -> String {
  case string.length(value) >= width {
    True -> value
    False -> left_pad("0" <> value, width)
  }
}
