import gleam/int
import gleam/list
import tasks/domain/model.{
  type Error, type Todo, AlreadyDone, Done, NotFound, Pending, Todo,
}

// BEAM integers are arbitrary precision, so max + 1 cannot overflow.
pub fn next_id(todos: List(Todo)) -> Int {
  todos
  |> list.fold(0, fn(current, task) { int.max(current, task.id) })
  |> int.add(1)
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
