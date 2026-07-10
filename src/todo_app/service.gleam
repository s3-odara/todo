import gleam/result
import tasks/domain/model.{
  type AddRequest, type DoneRequest, type Error, type ListRequest, type Todo,
  ListRequest,
}
import tasks/domain/tasks
import tasks/domain/validation
import todo_app/store.{type Store, Store}

pub type ServiceError {
  Domain(Error)
  Persisted(String)
}

pub fn add(store: Store, request: AddRequest) -> Result(Todo, ServiceError) {
  case validation.add(request) {
    Error(error) -> Error(Domain(error))
    Ok(values) ->
      persist_transition(store, fn(items) { Ok(tasks.add(items, values)) })
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
  case validation.done(request) {
    Error(error) -> Error(Domain(error))
    Ok(id) -> persist_transition(store, fn(items) { tasks.complete(items, id) })
  }
}

fn persist_transition(
  store: Store,
  transition: fn(List(Todo)) -> Result(#(List(Todo), Todo), Error),
) -> Result(Todo, ServiceError) {
  // Keep the read-write sequence here so domain transitions never receive a Store.
  let Store(load, save) = store
  case load() {
    Error(error) -> Error(Persisted(error))
    Ok(items) ->
      case transition(items) {
        Error(error) -> Error(Domain(error))
        Ok(#(updated, selected)) ->
          save(updated)
          |> result.map(fn(_) { selected })
          |> result.map_error(Persisted)
      }
  }
}
