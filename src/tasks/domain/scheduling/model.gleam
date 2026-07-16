import gleam/time/timestamp.{type Timestamp}

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

pub type ScheduleBlock {
  ScheduleBlock(task_id: Int, start: Timestamp, end: Timestamp)
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
