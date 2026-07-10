import gleam/int
import gleam/list
import tasks/domain/model.{
  type Error, type Todo, AlreadyDone, Done, NotFound, Pending, Todo,
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
  // Keep display order independent of mutable task metadata.
  todos
  |> list.filter(fn(t) { include_all || t.status == Pending })
  |> list.sort(by: fn(a, b) { int.compare(a.id, b.id) })
}
