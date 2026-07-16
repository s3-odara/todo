import gleam/result
import tasks/domain/app_state.{AppState}
import tasks/domain/availability.{type Availability, type Mutation}
import tasks/domain/filter.{type ResolvedListFilter}
import tasks/domain/model.{type TaskError, type Todo, type ValidatedAdd}
import tasks/domain/tasks
import todo_app/store.{type Store, Store}

pub type ServiceError {
  Domain(TaskError)
  Persisted(String)
}

pub fn add(store: Store, values: ValidatedAdd) -> Result(Todo, ServiceError) {
  persist_transition(store, fn(items) { Ok(tasks.add(items, values)) })
}

pub fn list(
  store: Store,
  filter: ResolvedListFilter,
) -> Result(List(Todo), ServiceError) {
  let Store(load, _) = store
  load()
  |> result.map(fn(state) {
    state.tasks
    |> tasks.visible(filter)
    |> tasks.sorted_by_id
  })
  |> result.map_error(Persisted)
}

pub fn done(store: Store, id: Int) -> Result(Todo, ServiceError) {
  persist_transition(store, fn(items) { tasks.complete(items, id) })
}

pub fn availability_list(store: Store) -> Result(Availability, ServiceError) {
  let Store(load, _) = store
  load()
  |> result.map(fn(state) { state.availability })
  |> result.map_error(Persisted)
}

pub fn mutate_availability(
  store: Store,
  mutation: Mutation,
) -> Result(Nil, ServiceError) {
  let Store(load, save) = store
  case load() {
    Error(error) -> Error(Persisted(error))
    Ok(state) -> {
      let #(updated, should_save) =
        availability.apply(state.availability, mutation)
      case should_save {
        False -> Ok(Nil)
        True ->
          save(AppState(..state, availability: updated))
          |> result.map_error(Persisted)
      }
    }
  }
}

fn persist_transition(
  store: Store,
  transition: fn(List(Todo)) -> Result(#(List(Todo), Todo), TaskError),
) -> Result(Todo, ServiceError) {
  // This is the single read-transform-write boundary; transitions stay pure.
  let Store(load, save) = store
  case load() {
    Error(error) -> Error(Persisted(error))
    Ok(state) ->
      case transition(state.tasks) {
        Error(error) -> Error(Domain(error))
        Ok(#(updated, selected)) ->
          save(AppState(..state, tasks: updated))
          |> result.map(fn(_) { selected })
          |> result.map_error(Persisted)
      }
  }
}
