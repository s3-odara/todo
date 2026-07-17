import filepath
import gleam/result
import simplifile
import tasks/domain/app_state.{type AppState, empty as empty_state}
import tasks/store/json

pub fn load(path: String) -> Result(AppState, String) {
  read_file(path)
  |> result.map_error(fn(error) { "read failed: " <> error })
  |> result.try(json.decode)
}

pub fn save(path: String, state: AppState) -> Result(Nil, String) {
  // A failed save may leave this behind; the next save simply overwrites it.
  let temporary = path <> ".tmp"

  simplifile.create_directory_all(filepath.directory_name(path))
  |> result.map_error(fn(error) {
    "create directory failed: " <> simplifile.describe_error(error)
  })
  |> result.try(fn(_) {
    simplifile.write(to: temporary, contents: json.encode(state))
    |> result.map_error(fn(error) {
      "temporary write failed: " <> simplifile.describe_error(error)
    })
  })
  |> result.try(fn(_) {
    simplifile.rename(temporary, path)
    |> result.map_error(fn(error) {
      "rename failed: " <> simplifile.describe_error(error)
    })
  })
}

fn read_file(path: String) -> Result(String, String) {
  case simplifile.read(path) {
    Ok(text) -> Ok(text)
    Error(simplifile.Enoent) -> Ok(json.encode(empty_state()))
    Error(error) -> Error(simplifile.describe_error(error))
  }
}
