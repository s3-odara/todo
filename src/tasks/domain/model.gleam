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

pub type AddRequest {
  AddRequest(
    title: String,
    estimate: String,
    priority: String,
    due: Option(String),
  )
}

pub type ListRequest {
  ListRequest(include_all: Bool)
}

pub type DoneRequest {
  DoneRequest(id: String)
}

pub type Error {
  InvalidTitle
  InvalidEstimate
  InvalidPriority
  InvalidDue
  InvalidId
  NotFound
  AlreadyDone
}
