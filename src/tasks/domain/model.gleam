import gleam/option.{type Option}

pub type Status {
  Pending
  Done
}

pub type Due {
  Due(canonical: String)
}

pub type Todo {
  Todo(
    id: Int,
    title: String,
    estimate_minutes: Int,
    priority: Int,
    due: Option(Due),
    status: Status,
  )
}

/// Values accepted by domain validation and ready for a pure task transition.
pub type ValidatedAdd {
  ValidatedAdd(
    title: String,
    estimate_minutes: Int,
    priority: Int,
    due: Option(Due),
  )
}

pub type Error {
  InvalidInput
  NotFound
  AlreadyDone
}
