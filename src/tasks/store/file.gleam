import filepath
import gleam/int
import gleam/result
import simplifile
import tasks/domain/model.{type Todo}
import tasks/runtime
import tasks/store/json

pub type FileOps {
  FileOps(
    read: fn(String) -> Result(String, String),
    write: fn(String, String) -> Result(Nil, String),
    rename: fn(String, String) -> Result(Nil, String),
    delete: fn(String) -> Result(Nil, String),
    mkdir: fn(String) -> Result(Nil, String),
  )
}

pub fn default_ops() -> FileOps {
  FileOps(read_file, write_file, rename_file, delete_file, make_directory)
}

pub fn load(path: String) -> Result(List(Todo), String) {
  load_with(default_ops(), path)
}

pub fn save(path: String, tasks: List(Todo)) -> Result(Nil, String) {
  save_with(default_ops(), path, tasks)
}

pub fn load_with(ops: FileOps, path: String) -> Result(List(Todo), String) {
  let FileOps(read, ..) = ops
  read(path)
  |> result.map_error(fn(e) { "read failed: " <> e })
  |> result.try(json.decode)
}

pub fn save_with(
  ops: FileOps,
  path: String,
  tasks: List(Todo),
) -> Result(Nil, String) {
  let FileOps(_, write, rename, delete, mkdir) = ops
  let parent = filepath.directory_name(path)
  let temporary = path <> ".tmp." <> int.to_string(runtime.unique_integer())
  let contents = json.encode(tasks)
  case mkdir(parent) {
    Error(e) -> Error("create directory failed: " <> e)
    Ok(_) ->
      case write(temporary, contents) {
        Error(e) -> {
          let _ = delete(temporary)
          Error("temporary write failed: " <> e)
        }
        Ok(_) ->
          case rename(temporary, path) {
            Ok(_) -> Ok(Nil)
            Error(e) -> {
              let _ = delete(temporary)
              Error("rename failed: " <> e)
            }
          }
      }
  }
}

fn read_file(path: String) -> Result(String, String) {
  case simplifile.read(path) {
    Ok(text) -> Ok(text)
    Error(simplifile.Enoent) -> Ok("[]")
    Error(e) -> Error(simplifile.describe_error(e))
  }
}

fn write_file(path: String, contents: String) -> Result(Nil, String) {
  simplifile.write(to: path, contents: contents)
  |> result.map_error(simplifile.describe_error)
}

fn rename_file(from: String, to: String) -> Result(Nil, String) {
  simplifile.rename(from, to) |> result.map_error(simplifile.describe_error)
}

fn delete_file(path: String) -> Result(Nil, String) {
  simplifile.delete_file(path) |> result.map_error(simplifile.describe_error)
}

fn make_directory(path: String) -> Result(Nil, String) {
  simplifile.create_directory_all(path)
  |> result.map_error(simplifile.describe_error)
}
