import filepath
import gleam/option.{type Option, None, Some}

pub fn resolve(
  todo_file: Option(String),
  xdg_data_home: Option(String),
  home: Option(String),
) -> Result(String, String) {
  case nonempty(todo_file) {
    Some(path) -> Ok(path)
    None ->
      case nonempty(xdg_data_home) {
        Some(path) ->
          Ok(filepath.join(filepath.join(path, "todo"), "tasks.yaml"))
        None ->
          case nonempty(home) {
            Some(path) ->
              Ok(filepath.join(
                filepath.join(filepath.join(path, ".local"), "share"),
                "todo/tasks.yaml",
              ))
            None -> Error("TODO_FILE, XDG_DATA_HOME, or HOME is required")
          }
      }
  }
}

fn nonempty(value: Option(String)) -> Option(String) {
  case value {
    Some(value) if value != "" -> Some(value)
    _ -> None
  }
}
