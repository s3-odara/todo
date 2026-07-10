import gleam/option.{Some}
import gleam/string
import gleeunit/should
import tasks/domain/model.{Done, Due, Todo}
import tasks/store/yaml

const valid = "tasks:\n  - id: 1\n    title: x\n    estimate_minutes: 0\n    priority: 3\n    due: null\n    status: pending\n"

pub fn round_trip_unicode_and_empty_encoding_test() {
  let tasks = [
    Todo(2, "日本語: # \\\"", 0, 5, Some(Due("2026-07-15T23:59")), Done),
  ]
  yaml.decode(yaml.encode(tasks)) |> should.equal(Ok(tasks))
  yaml.encode([]) |> should.equal("tasks: []\n")
  string.contains(yaml.encode(tasks), "version") |> should.equal(False)
  string.contains(yaml.encode(tasks), "schema") |> should.equal(False)
}

pub fn yaml_document_and_root_schema_matrix_test() {
  let assert Error(_) = yaml.decode("")
  let assert Error(_) = yaml.decode("tasks:")
  let assert Error(_) = yaml.decode("tasks: []\n---\ntasks: []\n")
  let assert Error(_) = yaml.decode("other: []\n")
  let assert Error(_) = yaml.decode("tasks: []\nversion: 1\n")
  let assert Error(_) = yaml.decode("tasks: {}\n")
  yaml.decode("tasks: []\n") |> should.equal(Ok([]))
}

pub fn reordered_valid_task_mapping_decodes_test() {
  yaml.decode(
    "tasks:\n  - status: done\n    due: \"2026-07-15T18:00\"\n    priority: 5\n    title: reordered\n    id: 7\n    estimate_minutes: 45\n",
  )
  |> should.equal(
    Ok([Todo(7, "reordered", 45, 5, Some(Due("2026-07-15T18:00")), Done)]),
  )
}

pub fn yaml_task_schema_and_value_matrix_test() {
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: 1\n    id: 2\n    title: x\n    estimate_minutes: 0\n    priority: 3\n    due: null\n    status: pending\n",
    )
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: 1\n    title: x\n    estimate_minutes: 0\n    priority: 3\n    due: null\n",
    )
  let assert Error(_) = yaml.decode(valid <> "    unknown: x\n")
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: x\n    title: x\n    estimate_minutes: 0\n    priority: 3\n    due: null\n    status: pending\n",
    )
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: 1\n    title: x\n    estimate_minutes: nope\n    priority: 3\n    due: null\n    status: pending\n",
    )
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: 1\n    title: x\n    estimate_minutes: 0\n    priority: 6\n    due: null\n    status: pending\n",
    )
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: 0\n    title: x\n    estimate_minutes: 0\n    priority: 3\n    due: null\n    status: pending\n",
    )
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: 1\n    title: x\n    estimate_minutes: 525601\n    priority: 3\n    due: null\n    status: pending\n",
    )
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: 1\n    title: x\n    estimate_minutes: 0\n    priority: 3\n    due: 2026-01-01\n    status: pending\n",
    )
  let assert Error(_) =
    yaml.decode(
      "tasks:\n  - id: 1\n    title: x\n    estimate_minutes: 0\n    priority: 3\n    due: null\n    status: later\n",
    )
  let assert Error(_) =
    yaml.decode(
      valid
      <> "  - id: 1\n    title: y\n    estimate_minutes: 0\n    priority: 3\n    due: null\n    status: done\n",
    )
}
