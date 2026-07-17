import gleam/time/timestamp.{type Timestamp}
import tasks/domain/policy.{type SchedulingPolicy}

pub type ExcludedReason {
  Completed
  MissingEstimate
  MissingDue
  DeadlineNotAfterStart
}

pub type ExcludedTask {
  ExcludedTask(task_id: Int, reason: ExcludedReason)
}

pub type UnscheduledTask {
  UnscheduledTask(task_id: Int, minutes: Int)
}

pub type PlanningContext {
  PlanningContext(
    generated_at: Timestamp,
    planning_start: Timestamp,
    utc_offset_seconds: Int,
  )
}

/// The immutable task projection accepted by the scheduling search.
/// Eligibility resolves the optional deadline before constructing this value.
pub type SchedulingTask {
  SchedulingTask(
    id: Int,
    estimate_minutes: Int,
    priority: Int,
    deadline_seconds: Int,
    scheduling_policy: SchedulingPolicy,
    minimum_split_minutes: Int,
  )
}

pub fn effective_minimum_split(task: SchedulingTask) -> Int {
  case task.estimate_minutes < task.minimum_split_minutes {
    True -> task.estimate_minutes
    False -> task.minimum_split_minutes
  }
}

pub type ScheduleBlock {
  ScheduleBlock(task_id: Int, start_seconds: Int, end_seconds: Int)
}

pub type SavedSchedule {
  SavedSchedule(
    generated_at: Timestamp,
    planning_start: Timestamp,
    utc_offset_seconds: Int,
    blocks: List(ScheduleBlock),
  )
}

pub type Score {
  Score(weighted_unscheduled_minutes: Int, weighted_policy_error: Float)
}

/// Derived generation details are deliberately not persisted.
pub type GenerationReport {
  GenerationReport(
    unscheduled: List(UnscheduledTask),
    excluded: List(ExcludedTask),
  )
}

pub type GenerationResult {
  GenerationResult(saved_schedule: SavedSchedule, report: GenerationReport)
}
