import gleam/int
import gleam/list
import tasks/domain/filter.{type StatusFilter, type TimeWindow}
import tasks/domain/model.{
  type TaskError, type Todo, type ValidatedAdd, AlreadyDone, Done, NotFound,
  Pending, Todo, ValidatedAdd,
}

// BEAM integers are arbitrary precision, so max + 1 cannot overflow.
fn next_id(todos: List(Todo)) -> Int {
  todos
  |> list.fold(0, fn(current, task) { int.max(current, task.id) })
  |> int.add(1)
}

pub fn add(todos: List(Todo), values: ValidatedAdd) -> #(List(Todo), Todo) {
  let ValidatedAdd(title, estimate, priority, due, policy, minimum_split) =
    values
  let added =
    Todo(
      next_id(todos),
      title,
      estimate,
      priority,
      due,
      Pending,
      policy,
      minimum_split,
    )
  #([added, ..todos], added)
}

pub fn complete(
  todos: List(Todo),
  wanted: Int,
) -> Result(#(List(Todo), Todo), TaskError) {
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

pub fn visible(
  todos: List(Todo),
  status: StatusFilter,
  window: TimeWindow,
) -> List(Todo) {
  list.filter(todos, fn(task) {
    filter.task_matches(status, window, task.status, task.due)
  })
}

pub fn sorted_by_id(todos: List(Todo)) -> List(Todo) {
  // Keep display order independent of mutable task metadata.
  list.sort(todos, by: fn(a, b) { int.compare(a.id, b.id) })
}
