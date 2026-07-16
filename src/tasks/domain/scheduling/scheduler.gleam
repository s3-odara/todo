import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/app_state.{type AppState, AppState}
import tasks/domain/due
import tasks/domain/scheduling/eligibility
import tasks/domain/scheduling/greedy
import tasks/domain/scheduling/hill_climb
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model.{
  type GenerationResult, type PlanningContext, GenerationReport,
  GenerationResult, PlanningContext, SavedSchedule, UnscheduledTask,
}
import tasks/domain/scheduling/score
import tasks/domain/scheduling/search.{SearchSpace}
import tasks/domain/scheduling/timeline

pub type SchedulingError {
  SearchSpaceTooLarge
  InvalidCalendarRange
  InvalidGeneratedSchedule
}

/// Capture and minute-ceil one clock observation using a fixed UTC offset.
pub fn context(now: Timestamp, utc_offset: Duration) -> PlanningContext {
  let #(seconds, nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(now)
  let #(offset_seconds, _) = duration.to_seconds_and_nanoseconds(utc_offset)
  let local_nanoseconds =
    { seconds + offset_seconds } * 1_000_000_000 + nanoseconds
  let minute_nanoseconds = 60_000_000_000
  let remainder = invariant.floor_mod(local_nanoseconds, minute_nanoseconds)
  let rounded = case remainder == 0 {
    True -> local_nanoseconds
    False -> local_nanoseconds + minute_nanoseconds - remainder
  }
  let planning_seconds = rounded / 1_000_000_000 - offset_seconds
  PlanningContext(
    timestamp.from_unix_seconds(seconds),
    timestamp.from_unix_seconds(planning_seconds),
    offset_seconds,
  )
}

/// Pure deterministic generation. This function performs no clock or store IO.
pub fn generate(
  state: AppState,
  context: PlanningContext,
) -> Result(GenerationResult, SchedulingError) {
  let AppState(tasks: all_tasks, availability: availability, ..) = state
  let PlanningContext(generated_at, planning_timestamp, offset) = context
  let planning_start = invariant.seconds(planning_timestamp)
  let eligibility.Classification(eligible, excluded) =
    eligibility.classify(all_tasks, planning_start)
  let horizon =
    list.fold(eligible, planning_start, fn(value, task) {
      case task.due {
        option.Some(deadline) -> int.max(value, due.to_unix_seconds(deadline))
        option.None -> value
      }
    })
  use projected <- result.try(
    timeline.project(availability, planning_start, horizon, offset)
    |> result.map_error(fn(error) {
      case error {
        timeline.SearchSpaceTooLarge -> SearchSpaceTooLarge
        timeline.InvalidCalendarRange -> InvalidCalendarRange
      }
    }),
  )
  let space = SearchSpace(projected, planning_start, offset)
  let initial = greedy.build(eligible, space)
  let blocks = hill_climb.improve(initial, eligible, space)
  use canonical <- result.try(
    invariant.validate_generation(blocks, eligible, space)
    |> result.map_error(fn(_) { InvalidGeneratedSchedule }),
  )
  let unscheduled =
    eligible
    |> list.map(fn(task) {
      UnscheduledTask(
        task.id,
        task.estimate_minutes - score.placed_minutes(task.id, canonical),
      )
    })
    |> list.filter(fn(entry) { entry.minutes > 0 })
  Ok(GenerationResult(
    SavedSchedule(generated_at, planning_timestamp, offset, canonical),
    GenerationReport(unscheduled, excluded),
  ))
}
