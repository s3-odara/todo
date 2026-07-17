import gleam/list
import gleam/option.{type Option, None, Some}
import tasks/domain/availability.{type Availability}
import tasks/domain/model.{type Todo}
import tasks/domain/scheduling/invariant as scheduling_invariant
import tasks/domain/scheduling/model as scheduling_model

pub type AppState {
  AppState(
    tasks: List(Todo),
    availability: Availability,
    current_schedule: Option(scheduling_model.SavedSchedule),
  )
}

pub fn empty() -> AppState {
  AppState([], availability.empty(), None)
}

/// Validate relationships and canonical shape across the aggregate.
/// Storage adapters translate representations; domain invariants stay here.
pub fn validate_aggregate(state: AppState) -> Result(AppState, Nil) {
  let AppState(tasks, available, current_schedule) = state
  case
    task_ids_are_unique(tasks)
    && availability.is_canonical(available)
    && schedule_is_valid(current_schedule, tasks)
  {
    True -> Ok(state)
    False -> Error(Nil)
  }
}

fn task_ids_are_unique(tasks: List(Todo)) -> Bool {
  let ids = list.map(tasks, fn(task) { task.id })
  ids == list.unique(ids)
}

fn schedule_is_valid(
  schedule: Option(scheduling_model.SavedSchedule),
  tasks: List(Todo),
) -> Bool {
  case schedule {
    None -> True
    Some(saved) ->
      scheduling_invariant.validate_persisted(
        saved.blocks,
        tasks,
        saved.utc_offset_seconds,
      )
      == Ok(Nil)
  }
}
