import tasks/domain/policy.{type SchedulingPolicy}
import tasks/domain/task_id.{type TaskId}

pub type ExcludedReason {
  Completed
  MissingEstimate
  MissingDue
  DeadlineNotAfterStart
}

pub type ExcludedTask {
  ExcludedTask(task_id: TaskId, reason: ExcludedReason)
}

pub type UnscheduledTask {
  UnscheduledTask(task_id: TaskId, minutes: Int)
}

// Scheduling calculations already use Unix seconds for deadlines and blocks.
// Keep timestamp conversion at the application boundary instead of mixing forms.
pub type PlanningContext {
  PlanningContext(
    generated_at_seconds: Int,
    planning_start_seconds: Int,
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

/// Integer task IDs are intentionally confined to the hot scheduling search.
/// Persisted blocks use UUIDs so they remain valid across devices and syncs.
pub type ScheduleBlock {
  ScheduleBlock(task_id: Int, start_seconds: Int, end_seconds: Int)
}

pub type SavedScheduleBlock {
  SavedScheduleBlock(task_id: TaskId, start_seconds: Int, end_seconds: Int)
}

pub type SavedSchedule {
  SavedSchedule(
    generated_at_seconds: Int,
    planning_start_seconds: Int,
    utc_offset_seconds: Int,
    blocks: List(SavedScheduleBlock),
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
