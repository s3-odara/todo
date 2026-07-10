import gleam/dynamic/decode
import gleam/json
import gleam/result
import tasks/domain/model.{
  type Due, type Status, type Todo, Done, Due, Pending, Todo,
}

pub fn decode(text: String) -> Result(List(Todo), String) {
  json.parse(from: text, using: decode.list(of: task_decoder()))
  |> result.map_error(fn(_) { "invalid JSON" })
}

fn task_decoder() {
  // The file is app-owned, so decode only the structure needed to rebuild a
  // Todo; do not revalidate domain values or reject unknown fields.
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  use estimate <- decode.field("estimate_minutes", decode.int)
  use priority <- decode.field("priority", decode.int)
  use due <- decode.field(
    "due",
    decode.optional(decode.string |> decode.map(Due)),
  )
  use status <- decode.field("status", status_decoder())
  decode.success(Todo(id, title, estimate, priority, due, status))
}

fn status_decoder() {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "pending" -> decode.success(Pending)
      "done" -> decode.success(Done)
      _ -> decode.failure(Pending, expected: "task status")
    }
  })
}

pub fn encode(todos: List(Todo)) -> String {
  json.array(todos, of: task_json) |> json.to_string
}

fn task_json(task: Todo) -> json.Json {
  json.object([
    #("id", json.int(task.id)),
    #("title", json.string(task.title)),
    #("estimate_minutes", json.int(task.estimate_minutes)),
    #("priority", json.int(task.priority)),
    #("due", json.nullable(task.due, of: due_json)),
    #("status", json.string(status_string(task.status))),
  ])
}

fn due_json(due: Due) -> json.Json {
  json.string(due.canonical)
}

fn status_string(status: Status) -> String {
  case status {
    Pending -> "pending"
    Done -> "done"
  }
}
