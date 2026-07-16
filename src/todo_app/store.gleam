import tasks/domain/app_state.{type AppState}

/// Injectable persistence boundary. Services never know paths or filesystems.
pub type Store {
  Store(
    load: fn() -> Result(AppState, String),
    save: fn(AppState) -> Result(Nil, String),
  )
}
