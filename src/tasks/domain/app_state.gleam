import gleam/option.{type Option, None}
import tasks/domain/availability.{type Availability}
import tasks/domain/model.{type Todo}
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
