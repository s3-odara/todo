import gleam/int
import gleam/list
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/app_state.{type AppState, AppState}
import tasks/domain/local_time
import tasks/domain/scheduling/eligibility
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model.{
  type GenerationResult, type PlanningContext, GenerationReport,
  GenerationResult, PlanningContext, SavedSchedule, SavedScheduleBlock,
  UnscheduledTask,
}
import tasks/domain/scheduling/score
import tasks/domain/scheduling/simple_sa
import tasks/domain/scheduling/timeline.{SearchSpace}

const production_seed = 101

pub type SchedulingError {
  SearchSpaceTooLarge
  InvalidGeneratedSchedule
}

/// Capture and minute-ceil one clock observation using a fixed UTC offset.
pub fn context(now: Timestamp, utc_offset: Duration) -> PlanningContext {
  let #(seconds, nanoseconds) = timestamp.to_unix_seconds_and_nanoseconds(now)
  let #(offset_seconds, _) = duration.to_seconds_and_nanoseconds(utc_offset)
  let local_nanoseconds =
    { seconds + offset_seconds } * 1_000_000_000 + nanoseconds
  let minute_nanoseconds = 60_000_000_000
  let remainder = local_time.floor_mod(local_nanoseconds, minute_nanoseconds)
  let rounded = case remainder == 0 {
    True -> local_nanoseconds
    False -> local_nanoseconds + minute_nanoseconds - remainder
  }
  let planning_seconds = rounded / 1_000_000_000 - offset_seconds
  PlanningContext(seconds, planning_seconds, offset_seconds)
}

/// Pure deterministic adaptive generation. This function performs no clock,
/// store, or entropy IO. Search randomness comes from the fixed production seed.
pub fn generate(
  state: AppState,
  context: PlanningContext,
) -> Result(GenerationResult, SchedulingError) {
  let AppState(tasks: all_tasks, availability: availability, ..) = state
  let PlanningContext(generated_at, planning_start, offset) = context
  let eligibility.Classification(eligible, excluded, identities) =
    eligibility.classify(all_tasks, planning_start)
  let horizon =
    list.fold(eligible, planning_start, fn(value, task) {
      int.max(value, task.deadline_seconds)
    })
  use projected <- result.try(
    timeline.project(availability, planning_start, horizon, offset)
    |> result.map_error(fn(error) {
      case error {
        timeline.SearchSpaceTooLarge -> SearchSpaceTooLarge
      }
    }),
  )
  let space = SearchSpace(projected, planning_start, offset)
  let blocks = simple_sa.improve(eligible, space, production_seed).blocks
  use _ <- result.try(
    invariant.validate_generation(blocks, eligible, space)
    |> result.map_error(fn(_) { InvalidGeneratedSchedule }),
  )
  let unscheduled =
    list.filter_map(eligible, fn(task) {
      let own = list.filter(blocks, fn(block) { block.task_id == task.id })
      let minutes = task.estimate_minutes - score.placed_minutes(own)
      case minutes > 0 {
        True -> Ok(UnscheduledTask(external_id(identities, task.id), minutes))
        False -> Error(Nil)
      }
    })
  let saved_blocks =
    list.map(blocks, fn(block) {
      SavedScheduleBlock(
        external_id(identities, block.task_id),
        block.start_seconds,
        block.end_seconds,
      )
    })
  Ok(GenerationResult(
    SavedSchedule(generated_at, planning_start, offset, saved_blocks),
    GenerationReport(unscheduled, excluded),
  ))
}

fn external_id(identities, index) {
  // Every search task is inserted into this table by eligibility.classify.
  let assert Ok(id) = list.key_find(identities, index)
  id
}
