import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/app_state.{type AppState, AppState}
import tasks/domain/availability.{type Availability, type Mutation}
import tasks/domain/filter.{type ResolvedListFilter, type ScheduledFilter}
import tasks/domain/model.{type TaskError, type Todo, type ValidatedAdd}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/scheduler.{type SchedulingError}
import tasks/domain/tasks
import todo_app/store.{type Store, Store}

pub type ServiceError {
  Domain(TaskError)
  Scheduling(SchedulingError)
  Persisted(String)
}

pub type ScheduledItem {
  ScheduledItem(block: scheduling_model.ScheduleBlock, task: Todo)
}

pub type ScheduledListing {
  ScheduledListing(utc_offset_seconds: Int, items: List(ScheduledItem))
}

type StateChange(value) {
  Persist(state: AppState, value: value)
  Keep(value: value)
}

pub fn add(store: Store, values: ValidatedAdd) -> Result(Todo, ServiceError) {
  persist_state(store, fn(state) {
    let #(updated, added) = tasks.add(state.tasks, values)
    Ok(Persist(AppState(..state, tasks: updated), added))
  })
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

pub fn generate_schedule(
  store: Store,
  context: scheduling_model.PlanningContext,
) -> Result(scheduling_model.GenerationResult, ServiceError) {
  persist_state(store, fn(state) {
    use generated <- result.try(
      scheduler.generate(state, context) |> result.map_error(Scheduling),
    )
    let scheduling_model.GenerationResult(saved_schedule, _) = generated
    Ok(Persist(
      AppState(..state, current_schedule: Some(saved_schedule)),
      generated,
    ))
  })
}

pub fn scheduled_list(
  store: Store,
  status: filter.StatusFilter,
  scheduled_filter: ScheduledFilter,
  now: Option(Timestamp),
) -> Result(ScheduledListing, ServiceError) {
  let Store(load, _) = store
  use state <- result.try(load() |> result.map_error(Persisted))
  case state.current_schedule {
    None -> Ok(ScheduledListing(0, []))
    Some(saved) -> {
      let offset = duration.seconds(saved.utc_offset_seconds)
      let window = filter.scheduled_window(scheduled_filter, now, offset)
      let items =
        saved.blocks
        |> list.filter_map(fn(block) {
          case find_task(state.tasks, block.task_id) {
            Some(task) ->
              case
                filter.status_matches(status, task.status)
                && filter.block_overlaps(block.start, block.end, window)
              {
                True -> Ok(ScheduledItem(block, task))
                False -> Error(Nil)
              }
            None -> Error(Nil)
          }
        })
        |> list.sort(by: fn(a, b) { invariant.block_compare(a.block, b.block) })
      Ok(ScheduledListing(saved.utc_offset_seconds, items))
    }
  }
}

pub fn done(store: Store, id: Int) -> Result(Todo, ServiceError) {
  persist_state(store, fn(state) {
    use #(updated, completed) <- result.try(
      tasks.complete(state.tasks, id) |> result.map_error(Domain),
    )
    Ok(Persist(AppState(..state, tasks: updated), completed))
  })
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
  persist_state(store, fn(state) {
    let #(updated, changed) = availability.apply(state.availability, mutation)
    case changed {
      True -> Ok(Persist(AppState(..state, availability: updated), Nil))
      False -> Ok(Keep(Nil))
    }
  })
}

fn find_task(tasks: List(Todo), id: Int) -> Option(Todo) {
  case tasks {
    [] -> None
    [task, ..rest] ->
      case task.id == id {
        True -> Some(task)
        False -> find_task(rest, id)
      }
  }
}

fn persist_state(
  store: Store,
  transition: fn(AppState) -> Result(StateChange(value), ServiceError),
) -> Result(value, ServiceError) {
  // Store effects stay here; callers only describe an immutable state change.
  let Store(load, save) = store
  use state <- result.try(load() |> result.map_error(Persisted))
  use change <- result.try(transition(state))
  case change {
    Keep(value) -> Ok(value)
    Persist(updated, value) ->
      save(updated)
      |> result.map_error(Persisted)
      |> result.map(fn(_) { value })
  }
}
