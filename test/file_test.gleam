import gleam/int
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import tasks/runtime
import tasks/store/file.{type FileOps, FileOps, load_with, save_with}

type Recorder {
  Recorder(trace: String, write_bytes: String)
}

fn ok_ops() -> FileOps {
  FileOps(
    fn(_) { Ok("[]") },
    fn(_, _) { Ok(Nil) },
    fn(_, _) { Ok(Nil) },
    fn(_) { Ok(Nil) },
    fn(_) { Ok(Nil) },
  )
}

fn new_recorder(root: String) -> Recorder {
  let trace = root <> "/operations"
  let write_bytes = root <> "/write-bytes"
  let assert Ok(Nil) = simplifile.write(to: trace, contents: "")
  let assert Ok(Nil) = simplifile.write(to: write_bytes, contents: "")
  Recorder(trace, write_bytes)
}

fn record(recorder: Recorder, operation: String) -> Nil {
  let Recorder(trace, _) = recorder
  let assert Ok(Nil) = simplifile.append(to: trace, contents: operation <> "\n")
  Nil
}

fn record_write(recorder: Recorder, path: String, contents: String) -> Nil {
  let Recorder(_, write_bytes) = recorder
  record(recorder, "write\t" <> path)
  let assert Ok(Nil) = simplifile.write(to: write_bytes, contents: contents)
  Nil
}

fn fixture_root(name: String) -> String {
  "/tmp/todo-app-file-test-"
  <> name
  <> "-"
  <> int.to_string(runtime.unique_integer())
}

fn cleanup(root: String) {
  let _ = simplifile.delete_all([root])
}

pub fn injected_read_failure_test() {
  let FileOps(_, write, rename, delete, mkdir) = ok_ops()
  load_with(
    FileOps(fn(_) { Error("denied") }, write, rename, delete, mkdir),
    "/x",
  )
  |> should.equal(Error("read failed: denied"))
}

pub fn injected_write_failure_records_cleanup_paths_order_and_bytes_test() {
  let root = fixture_root("write")
  let destination = root <> "/todo/tasks.json"
  let original = "existing destination bytes"
  let assert Ok(Nil) = simplifile.create_directory_all(root <> "/todo")
  let assert Ok(Nil) = simplifile.write(to: destination, contents: original)
  let recorder = new_recorder(root)
  let FileOps(read, rename, _, _, _) = ok_ops()
  let ops =
    FileOps(
      read,
      fn(path, contents) {
        record_write(recorder, path, contents)
        let assert Ok(Nil) = simplifile.write(to: path, contents: contents)
        Error("disk full")
      },
      rename,
      fn(path) {
        record(recorder, "delete\t" <> path)
        simplifile.delete_file(at: path)
        |> result.map_error(simplifile.describe_error)
      },
      fn(path) {
        record(recorder, "mkdir\t" <> path)
        simplifile.create_directory_all(path)
        |> result.map_error(simplifile.describe_error)
      },
    )
  save_with(ops, destination, [])
  |> should.equal(Error("temporary write failed: disk full"))
  let assert Ok(trace) = simplifile.read(from: root <> "/operations")
  let assert [mkdir, write, delete] = string.split(trace, "\n") |> drop_last
  let assert ["mkdir", parent] = string.split(mkdir, "\t")
  let assert ["write", temporary] = string.split(write, "\t")
  let assert ["delete", cleanup_path] = string.split(delete, "\t")
  parent |> should.equal(root <> "/todo")
  string.starts_with(temporary, destination <> ".tmp.") |> should.equal(True)
  cleanup_path |> should.equal(temporary)
  simplifile.read(from: root <> "/write-bytes")
  |> should.equal(Ok("[]"))
  simplifile.read(from: destination) |> should.equal(Ok(original))
  simplifile.read(from: temporary) |> should.equal(Error(simplifile.Enoent))
  cleanup(root)
}

pub fn injected_rename_failure_records_cleanup_paths_order_and_bytes_test() {
  let root = fixture_root("rename")
  let destination = root <> "/todo/tasks.json"
  let original = "existing destination bytes"
  let assert Ok(Nil) = simplifile.create_directory_all(root <> "/todo")
  let assert Ok(Nil) = simplifile.write(to: destination, contents: original)
  let recorder = new_recorder(root)
  let FileOps(read, _, _, _, _) = ok_ops()
  let ops =
    FileOps(
      read,
      fn(path, contents) {
        record_write(recorder, path, contents)
        simplifile.write(to: path, contents: contents)
        |> result.map_error(simplifile.describe_error)
      },
      fn(from, to) {
        record(recorder, "rename\t" <> from <> "\t" <> to)
        Error("rename denied")
      },
      fn(path) {
        record(recorder, "delete\t" <> path)
        simplifile.delete_file(at: path)
        |> result.map_error(simplifile.describe_error)
      },
      fn(path) {
        record(recorder, "mkdir\t" <> path)
        simplifile.create_directory_all(path)
        |> result.map_error(simplifile.describe_error)
      },
    )
  save_with(ops, destination, [])
  |> should.equal(Error("rename failed: rename denied"))
  let assert Ok(trace) = simplifile.read(from: root <> "/operations")
  let assert [mkdir, write, rename, delete] =
    string.split(trace, "\n") |> drop_last
  let assert ["mkdir", parent] = string.split(mkdir, "\t")
  let assert ["write", temporary] = string.split(write, "\t")
  let assert ["rename", from, to] = string.split(rename, "\t")
  let assert ["delete", cleanup_path] = string.split(delete, "\t")
  parent |> should.equal(root <> "/todo")
  string.starts_with(temporary, destination <> ".tmp.") |> should.equal(True)
  from |> should.equal(temporary)
  to |> should.equal(destination)
  cleanup_path |> should.equal(temporary)
  simplifile.read(from: root <> "/write-bytes")
  |> should.equal(Ok("[]"))
  simplifile.read(from: destination) |> should.equal(Ok(original))
  simplifile.read(from: temporary) |> should.equal(Error(simplifile.Enoent))
  cleanup(root)
}

fn drop_last(items: List(String)) -> List(String) {
  case items {
    [] -> []
    [_first] -> []
    [first, ..rest] -> [first, ..drop_last(rest)]
  }
}

pub fn injected_load_empty_test() {
  load_with(ok_ops(), "/x/tasks.json") |> should.equal(Ok([]))
}

pub fn injected_mkdir_failure_test() {
  let FileOps(read, write, rename, delete, _) = ok_ops()
  save_with(
    FileOps(read, write, rename, delete, fn(_) { Error("mkdir denied") }),
    "/x/new/tasks.json",
    [],
  )
  |> should.equal(Error("create directory failed: mkdir denied"))
}
