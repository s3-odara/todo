import gleam/option.{type Option, None}
import tasks/domain/availability.{type Availability}
import tasks/domain/model.{type Todo}
import tasks/domain/scheduling/model as scheduling_model

pub type AppState {
  AppState(
    version: Int,
    tasks: List(Todo),
    availability: Availability,
    current_schedule: Option(scheduling_model.SavedSchedule),
  )
}

pub fn empty() -> AppState {
  AppState(1, [], availability.empty(), None)
}
