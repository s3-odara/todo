import gleam/list
import gleam/option
import gleam/result
import tasks/domain/filter.{type StatusFilter, type TimeWindow}
import tasks/domain/model.{
  type AddValues, type Status, type TaskError, type Todo, type UpdateValues,
  AddValues, AlreadyDone, AlreadyPending, AmbiguousId, Done, NotFound, Pending,
  Todo, UpdateValues,
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
  set_status(todos, wanted, Done)
}

pub fn reopen(
  todos: List(Todo),
  wanted: TaskId,
) -> Result(#(List(Todo), Todo), TaskError) {
  set_status(todos, wanted, Pending)
}

// Keep the intent-focused CLI commands while sharing their status transition.
fn set_status(
  todos: List(Todo),
  wanted: TaskId,
  status: Status,
) -> Result(#(List(Todo), Todo), TaskError) {
  case list.find(todos, fn(task) { task.id == wanted }) {
    Error(_) -> Error(NotFound)
    Ok(Todo(status: current, ..)) if current == status ->
      case status {
        Done -> Error(AlreadyDone)
        Pending -> Error(AlreadyPending)
      }
    Ok(task) -> {
      let changed = Todo(..task, status: status)
      Ok(#(replace(todos, changed), changed))
    }
  }
}

pub fn update(
  todos: List(Todo),
  wanted: TaskId,
  values: UpdateValues,
) -> Result(#(List(Todo), Todo), TaskError) {
  use task <- result.try(
    list.find(todos, fn(task) { task.id == wanted })
    |> result.map_error(fn(_) { NotFound }),
  )
  let UpdateValues(title, estimate, priority, due, policy, minimum_split) =
    values
  let changed =
    Todo(
      ..task,
      title: option.unwrap(title, task.title),
      estimate_minutes: option.unwrap(estimate, task.estimate_minutes),
      priority: option.unwrap(priority, task.priority),
      due: option.unwrap(due, task.due),
      scheduling_policy: option.unwrap(policy, task.scheduling_policy),
      minimum_split_minutes: option.unwrap(
        minimum_split,
        task.minimum_split_minutes,
      ),
    )
  Ok(#(replace(todos, changed), changed))
}

pub fn delete(
  todos: List(Todo),
  wanted: TaskId,
) -> Result(#(List(Todo), Todo), TaskError) {
  use task <- result.try(
    list.find(todos, fn(task) { task.id == wanted })
    |> result.map_error(fn(_) { NotFound }),
  )
  Ok(#(list.filter(todos, fn(current) { current.id != wanted }), task))
}

fn replace(todos: List(Todo), changed: Todo) -> List(Todo) {
  list.map(todos, fn(current) {
    case current.id == changed.id {
      True -> changed
      False -> current
    }
  })
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
