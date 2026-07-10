import tasks/domain/model.{type Todo}

/// Injectable persistence boundary. Services never know paths or filesystems.
pub type Store {
  Store(
    load: fn() -> Result(List(Todo), String),
    save: fn(List(Todo)) -> Result(Nil, String),
  )
}
