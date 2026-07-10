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
  case list.find(todos, fn(task) { task.id == wanted }) {
    Error(_) -> Error(NotFound)
    Ok(Todo(status: Done, ..)) -> Error(AlreadyDone)
    Ok(task) -> {
      let completed = Todo(..task, status: Done)
      // IDs created by the app are unique; replacing by ID keeps the update clear.
      let updated =
        list.map(todos, fn(current) {
          case current.id == wanted {
            True -> completed
            False -> current
          }
        })
      Ok(#(updated, completed))
    }
  }
}

pub fn visible_sorted(todos: List(Todo), include_all: Bool) -> List(Todo) {
  // Keep display order independent of mutable task metadata.
  todos
  |> list.filter(fn(t) { include_all || t.status == Pending })
  |> list.sort(by: fn(a, b) { int.compare(a.id, b.id) })
}
