import gleam/option.{type Option, None, Some}
import gleam/result
import tasks/domain/due
import tasks/domain/model.{
  type AddRequest, type DoneRequest, type Due, type Error, type ListRequest,
  type Todo, AddRequest, DoneRequest, ListRequest, Pending, Todo,
}
import tasks/domain/tasks
import tasks/domain/validation
import todo_app/store.{type Store, Store}

pub type ServiceError {
  Input(Error)
  Persisted(String)
}

pub fn add(store: Store, request: AddRequest) -> Result(Todo, ServiceError) {
  let AddRequest(title, estimate, priority, raw_due) = request
  case
    validation.title(title),
    validation.estimate(estimate),
    validation.priority(priority),
    parse_due(raw_due)
  {
    Ok(clean), Ok(minutes), Ok(rank), Ok(due_value) -> {
      let Store(load, save) = store
      case load() {
        Error(e) -> Error(Persisted(e))
        Ok(items) -> {
          let added =
            Todo(tasks.next_id(items), clean, minutes, rank, due_value, Pending)
          save([added, ..items])
          |> result.map(fn(_) { added })
          |> result.map_error(Persisted)
        }
      }
    }
    Error(e), _, _, _ -> Error(Input(e))
    _, Error(e), _, _ -> Error(Input(e))
    _, _, Error(e), _ -> Error(Input(e))
    _, _, _, Error(e) -> Error(Input(e))
  }
}

pub fn list(
  store: Store,
  request: ListRequest,
) -> Result(List(Todo), ServiceError) {
  let Store(load, _) = store
  let ListRequest(all) = request
  load()
  |> result.map(fn(items) { tasks.visible_sorted(items, all) })
  |> result.map_error(Persisted)
}

pub fn done(store: Store, request: DoneRequest) -> Result(Todo, ServiceError) {
  let DoneRequest(raw_id) = request
  case validation.id(raw_id) {
    Error(e) -> Error(Input(e))
    Ok(id) -> {
      let Store(load, save) = store
      case load() {
        Error(e) -> Error(Persisted(e))
        Ok(items) ->
          case tasks.complete(items, id) {
            Error(e) -> Error(Input(e))
            Ok(#(updated, completed)) ->
              save(updated)
              |> result.map(fn(_) { completed })
              |> result.map_error(Persisted)
          }
      }
    }
  }
}

fn parse_due(raw: Option(String)) -> Result(Option(Due), Error) {
  case raw {
    None -> Ok(None)
    Some(value) -> due.input(value) |> result.map(Some)
  }
}
