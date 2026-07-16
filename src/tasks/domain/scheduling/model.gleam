import gleam/time/timestamp.{type Timestamp}

pub type PlanningContext {
  PlanningContext(planning_start: Timestamp, utc_offset_seconds: Int)
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
