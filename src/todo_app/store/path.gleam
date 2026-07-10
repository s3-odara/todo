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
        Some(path) -> Ok(tasks_file(path))
        None ->
          case nonempty(home) {
            Some(path) ->
              Ok(
                tasks_file(filepath.join(filepath.join(path, ".local"), "share")),
              )
            None -> Error("TODO_FILE, XDG_DATA_HOME, or HOME is required")
          }
      }
  }
}

fn tasks_file(data_home: String) -> String {
  filepath.join(filepath.join(data_home, "todo"), "tasks.yaml")
}

fn nonempty(value: Option(String)) -> Option(String) {
  case value {
    Some(value) if value != "" -> Some(value)
    _ -> None
  }
}
