import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import tasks/domain/model.{
  type Due, type Error, type Status, type Todo, AlreadyDone, Done, Due, NotFound,
  Pending, Todo,
}

pub fn next_id(todos: List(Todo)) -> Result(Int, Error) {
  max_id(todos, 0)
}

fn max_id(todos: List(Todo), current: Int) -> Result(Int, Error) {
  case todos {
    [] -> Ok(current + 1)
    [Todo(id: id, ..), ..rest] ->
      // Erlang integers are arbitrary precision, so every valid persisted ID
      // has a representable successor on this target.
      max_id(rest, case id > current {
        True -> id
        False -> current
      })
  }
}

pub fn complete(
  todos: List(Todo),
  wanted: Int,
) -> Result(#(List(Todo), Todo), Error) {
  complete_loop(todos, wanted, [])
}

fn complete_loop(
  todos: List(Todo),
  wanted: Int,
  before: List(Todo),
) -> Result(#(List(Todo), Todo), Error) {
  case todos {
    [] -> Error(NotFound)
    [Todo(id: id, status: Done, ..), ..] if id == wanted -> Error(AlreadyDone)
    [
      Todo(
        id: id,
        title: title,
        estimate_minutes: estimate,
        priority: priority,
        due: due,
        ..,
      ),
      ..rest
    ]
      if id == wanted
    -> {
      let completed = Todo(id, title, estimate, priority, due, Done)
      Ok(#(list.reverse(before) |> list.append([completed, ..rest]), completed))
    }
    [task, ..rest] -> complete_loop(rest, wanted, [task, ..before])
  }
}

pub fn visible_sorted(todos: List(Todo), include_all: Bool) -> List(Todo) {
  todos
  |> list.filter(fn(t) { include_all || t.status == Pending })
  |> insertion([])
}

fn insertion(items: List(Todo), acc: List(Todo)) -> List(Todo) {
  case items {
    [] -> acc
    [item, ..rest] -> insertion(rest, insert(item, acc))
  }
}

fn insert(item: Todo, items: List(Todo)) -> List(Todo) {
  case items {
    [] -> [item]
    [head, ..rest] ->
      case before(item, head) {
        True -> [item, head, ..rest]
        False -> [head, ..insert(item, rest)]
      }
  }
}

fn before(a: Todo, b: Todo) -> Bool {
  case status_rank(a.status) < status_rank(b.status) {
    True -> True
    False ->
      case status_rank(a.status) > status_rank(b.status) {
        True -> False
        False -> due_before(a.due, b.due, a.priority, b.priority, a.id, b.id)
      }
  }
}

fn status_rank(s: Status) -> Int {
  case s {
    Pending -> 0
    Done -> 1
  }
}

fn due_before(
  a: Option(Due),
  b: Option(Due),
  ap: Int,
  bp: Int,
  ai: Int,
  bi: Int,
) -> Bool {
  case a, b {
    Some(Due(x)), Some(Due(y)) ->
      case string_less(x, y) {
        True -> True
        False ->
          case x == y {
            True -> tie(ap, bp, ai, bi)
            False -> False
          }
      }
    Some(_), None -> True
    None, Some(_) -> False
    None, None -> tie(ap, bp, ai, bi)
  }
}

fn string_less(a: String, b: String) -> Bool {
  case string.to_utf_codepoints(a), string.to_utf_codepoints(b) {
    [], _ -> False
    [_, ..], [] -> False
    [x, ..xs], [y, ..ys] ->
      case string.utf_codepoint_to_int(x) < string.utf_codepoint_to_int(y) {
        True -> True
        False ->
          case x == y {
            True ->
              string_less(
                string.from_utf_codepoints(xs),
                string.from_utf_codepoints(ys),
              )
            False -> False
          }
      }
  }
}

fn tie(ap: Int, bp: Int, ai: Int, bi: Int) -> Bool {
  case ap > bp {
    True -> True
    False ->
      case ap < bp {
        True -> False
        False -> ai < bi
      }
  }
}
