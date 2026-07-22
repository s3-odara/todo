import gleam/option.{type Option}
import tasks/domain/due.{type Due}
import tasks/domain/policy.{type SchedulingPolicy}

pub type Status {
  Pending
  Done
}

pub fn parse_status(value: String) -> Result(Status, Nil) {
  case value {
    "pending" -> Ok(Pending)
    "done" -> Ok(Done)
    _ -> Error(Nil)
  }
}

pub fn status_to_string(status: Status) -> String {
  case status {
    Pending -> "pending"
    Done -> "done"
  }
}

pub type Todo {
  Todo(
    id: Int,
    title: String,
    estimate_minutes: Int,
    priority: Int,
    due: Option(Due),
    status: Status,
    scheduling_policy: SchedulingPolicy,
    minimum_split_minutes: Int,
  )
}

/// Values needed to create a task before its ID and status are assigned.
pub type AddValues {
  AddValues(
    title: String,
    estimate_minutes: Int,
    priority: Int,
    due: Option(Due),
    scheduling_policy: SchedulingPolicy,
    minimum_split_minutes: Int,
  )
}

pub type TaskError {
  NotFound
  AlreadyDone
}
