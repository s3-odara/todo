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

/// Values accepted by domain validation and ready for a pure task transition.
pub type ValidatedAdd {
  ValidatedAdd(
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
