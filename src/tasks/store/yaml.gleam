import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import taffy
import taffy/value.{Int, Mapping, Null, Sequence, String}
import tasks/domain/due
import tasks/domain/model.{type Due, type Todo, Done, Due, Pending, Todo}
import tasks/domain/validation

pub fn decode(text: String) -> Result(List(Todo), String) {
  case taffy.parse_all(text) {
    Error(_) -> Error("invalid YAML")
    Ok([value]) ->
      case taffy.validate_unique_keys(value) {
        Ok(valid) -> decode_root(valid)
        Error(_) -> Error("duplicate YAML key")
      }
    Ok(_) -> Error("YAML must contain exactly one document")
  }
}

fn decode_root(value) -> Result(List(Todo), String) {
  case taffy.as_pairs(value) {
    Some([#("tasks", tasks)]) ->
      case taffy.as_list(tasks) {
        Some(items) -> decode_tasks(items)
        None -> Error("tasks must be a sequence")
      }
    _ -> Error("YAML top level must contain only tasks")
  }
}

fn decode_tasks(items) -> Result(List(Todo), String) {
  list.try_map(items, decode_task) |> result.try(unique)
}

// Mapping order is intentionally irrelevant. validate_unique_keys above keeps
// this lookup safe while exact_keys rejects both missing and unknown fields.
fn decode_task(value) -> Result(Todo, String) {
  case taffy.as_pairs(value) {
    Some(pairs) ->
      case
        exact_keys(pairs, [
          "id",
          "title",
          "estimate_minutes",
          "priority",
          "due",
          "status",
        ])
      {
        True ->
          case
            get(pairs, "id"),
            get(pairs, "title"),
            get(pairs, "estimate_minutes"),
            get(pairs, "priority"),
            get(pairs, "due"),
            get(pairs, "status")
          {
            Some(Int(id)),
              Some(String(title)),
              Some(Int(estimate)),
              Some(Int(priority)),
              Some(raw_due),
              Some(String(status))
            ->
              case
                validation.id(int.to_string(id)),
                validation.title(title),
                decode_due(raw_due)
              {
                Ok(_), Ok(clean_title), Ok(due_value)
                  if estimate >= 0
                  && estimate <= 525_600
                  && priority >= 1
                  && priority <= 5
                ->
                  case status {
                    "pending" ->
                      Ok(Todo(
                        id,
                        clean_title,
                        estimate,
                        priority,
                        due_value,
                        Pending,
                      ))
                    "done" ->
                      Ok(Todo(
                        id,
                        clean_title,
                        estimate,
                        priority,
                        due_value,
                        Done,
                      ))
                    _ -> Error("invalid persisted task")
                  }
                _, _, _ -> Error("invalid persisted task")
              }
            _, _, _, _, _, _ -> Error("task schema is invalid")
          }
        False -> Error("task schema is invalid")
      }
    _ -> Error("task schema is invalid")
  }
}

fn exact_keys(pairs, expected: List(String)) -> Bool {
  list.length(pairs) == list.length(expected)
  && list.all(expected, fn(key) {
    case get(pairs, key) {
      Some(_) -> True
      None -> False
    }
  })
}

fn get(pairs, wanted: String) {
  list.key_find(pairs, wanted) |> option.from_result
}

fn decode_due(value) -> Result(Option(Due), String) {
  case value {
    Null -> Ok(None)
    String(s) ->
      due.persisted(s)
      |> result.map(Some)
      |> result.map_error(fn(_) { "invalid persisted due" })
    _ -> Error("due must be string or null")
  }
}

fn unique(todos: List(Todo)) -> Result(List(Todo), String) {
  // Compare counts instead of silently discarding tasks with duplicate IDs.
  let ids = list.map(todos, fn(task) { task.id })
  case list.length(list.unique(ids)) == list.length(ids) {
    True -> Ok(todos)
    False -> Error("duplicate task id")
  }
}

pub fn encode(todos: List(Todo)) -> String {
  Mapping([#("tasks", Sequence(list.map(todos, task_value)))]) |> taffy.to_yaml
}

fn task_value(task: Todo) {
  Mapping([
    #("id", Int(task.id)),
    #("title", String(task.title)),
    #("estimate_minutes", Int(task.estimate_minutes)),
    #("priority", Int(task.priority)),
    #("due", due_value(task.due)),
    #(
      "status",
      String(case task.status {
        Pending -> "pending"
        Done -> "done"
      }),
    ),
  ])
}

fn due_value(value: Option(Due)) {
  case value {
    None -> Null
    Some(Due(s)) -> String(s)
  }
}
