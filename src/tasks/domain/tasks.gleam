import gleam/list
import tasks/domain/filter.{type StatusFilter, type TimeWindow}
import tasks/domain/model.{
  type AddValues, type TaskError, type Todo, AddValues, AlreadyDone, AmbiguousId,
  Done, NotFound, Pending, Todo,
}
import tasks/domain/task_id.{type TaskId}

pub fn add(
  todos: List(Todo),
  id: TaskId,
  values: AddValues,
) -> #(List(Todo), Todo) {
  let AddValues(title, estimate, priority, due, policy, minimum_split) = values
  let added =
    Todo(id, title, estimate, priority, due, Pending, policy, minimum_split)
  #([added, ..todos], added)
}

pub fn resolve_id(
  todos: List(Todo),
  normalized_selector: String,
) -> Result(TaskId, TaskError) {
  let matches =
    list.filter(todos, fn(task) {
      task_id.matches_selector(task.id, normalized_selector)
    })
  case matches {
    [] -> Error(NotFound)
    [task] -> Ok(task.id)
    _ -> Error(AmbiguousId)
  }
}

pub fn complete(
  todos: List(Todo),
  wanted: TaskId,
) -> Result(#(List(Todo), Todo), TaskError) {
  case list.find(todos, fn(task) { task.id == wanted }) {
    Error(_) -> Error(NotFound)
    Ok(Todo(status: Done, ..)) -> Error(AlreadyDone)
    Ok(task) -> {
      let completed = Todo(..task, status: Done)
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
  list.sort(todos, by: fn(a, b) { task_id.compare(a.id, b.id) })
}
