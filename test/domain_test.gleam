import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{
  AddRequest, AlreadyDone, Done, DoneRequest, Due, InvalidInput, NotFound,
  Pending, Todo, ValidatedAdd,
}
import tasks/domain/tasks
import tasks/domain/validation

fn validated_add(title: String, estimate: String, priority: String) {
  validation.add(AddRequest(title, estimate, priority, None))
}

pub fn title_validation_test() {
  validated_add(" clean ", "0m", "3")
  |> should.equal(Ok(ValidatedAdd("clean", 0, 3, None)))
  validated_add("", "0m", "3") |> should.equal(Error(InvalidInput))
  validated_add("   ", "0m", "3") |> should.equal(Error(InvalidInput))
  validated_add("\tclean", "0m", "3") |> should.equal(Error(InvalidInput))
  validated_add("clean\n", "0m", "3") |> should.equal(Error(InvalidInput))
  validated_add("clean\r", "0m", "3") |> should.equal(Error(InvalidInput))
  validated_add("clean\u{0}", "0m", "3") |> should.equal(Error(InvalidInput))
  validated_add("a", "0m", "3")
  |> should.equal(Ok(ValidatedAdd("a", 0, 3, None)))
  validated_add(string.repeat("a", 200), "0m", "3")
  |> should.equal(Ok(ValidatedAdd(string.repeat("a", 200), 0, 3, None)))
  validated_add(string.repeat("a", 201), "0m", "3")
  |> should.equal(Error(InvalidInput))
}

pub fn estimate_validation_test() {
  validated_add("x", "0m", "3")
  |> should.equal(Ok(ValidatedAdd("x", 0, 3, None)))
  validated_add("x", "0h", "3")
  |> should.equal(Ok(ValidatedAdd("x", 0, 3, None)))
  validated_add("x", "8760h", "3")
  |> should.equal(Ok(ValidatedAdd("x", 525_600, 3, None)))
  validated_add("x", "525600m", "3")
  |> should.equal(Ok(ValidatedAdd("x", 525_600, 3, None)))
  ["525601m", "8761h", "01m", "1h30m", "1.5h", "3H", "-1m", "1"]
  |> list.each(fn(value) {
    validated_add("x", value, "3") |> should.equal(Error(InvalidInput))
  })
}

pub fn priority_validation_test() {
  validated_add("x", "0m", "1")
  |> should.equal(Ok(ValidatedAdd("x", 0, 1, None)))
  validated_add("x", "0m", "5")
  |> should.equal(Ok(ValidatedAdd("x", 0, 5, None)))
  ["0", "6", "01", "x"]
  |> list.each(fn(value) {
    validated_add("x", "0m", value) |> should.equal(Error(InvalidInput))
  })
}

pub fn id_validation_test() {
  validation.done(DoneRequest("1")) |> should.equal(Ok(1))
  validation.done(DoneRequest("2147483648"))
  |> should.equal(Ok(2_147_483_648))
  ["0", "01", "1x"]
  |> list.each(fn(value) {
    validation.done(DoneRequest(value)) |> should.equal(Error(InvalidInput))
  })
}

pub fn due_calendar_and_rejection_matrix_test() {
  due.input("2024-02-29") |> should.equal(Ok(Due("2024-02-29T23:59")))
  due.input("2023-02-29") |> should.equal(Error(InvalidInput))
  due.input("2026-04-31") |> should.equal(Error(InvalidInput))
  due.input("2026-12-31T23:59") |> should.equal(Ok(Due("2026-12-31T23:59")))
  due.input("2026-01-01T24:00") |> should.equal(Error(InvalidInput))
  due.input("2026-01-01T12:60") |> should.equal(Error(InvalidInput))
  due.input("2026-01-01T12:00Z") |> should.equal(Error(InvalidInput))
  due.input("2026-01-01T12:00+09:00") |> should.equal(Error(InvalidInput))
  due.input("2026-01-01T12:00:01") |> should.equal(Error(InvalidInput))
  due.input("2026-01-01T12:00.1") |> should.equal(Error(InvalidInput))
  due.input("2026-01-01t12:00") |> should.equal(Error(InvalidInput))
  due.input("2026-01-01 12:00") |> should.equal(Error(InvalidInput))
}

pub fn validated_add_is_a_pure_transition_test() {
  let request = AddRequest(" write report ", "2h", "4", Some("2026-07-15"))
  let assert Ok(values) = validation.add(request)
  values
  |> should.equal(ValidatedAdd(
    "write report",
    120,
    4,
    Some(Due("2026-07-15T23:59")),
  ))

  let existing = Todo(2, "old", 0, 3, None, Pending)
  tasks.add([existing], values)
  |> should.equal(#(
    [
      Todo(3, "write report", 120, 4, Some(Due("2026-07-15T23:59")), Pending),
      existing,
    ],
    Todo(3, "write report", 120, 4, Some(Due("2026-07-15T23:59")), Pending),
  ))
}

pub fn next_id_uses_the_largest_existing_id_test() {
  let existing = Todo(2_147_483_647, "max", 0, 3, None, Done)
  tasks.add([existing], ValidatedAdd("new", 0, 3, None))
  |> should.equal(#(
    [Todo(2_147_483_648, "new", 0, 3, None, Pending), existing],
    Todo(2_147_483_648, "new", 0, 3, None, Pending),
  ))
}

pub fn visible_tasks_filter_and_sort_test() {
  let values = [
    Todo(2_147_483_647, "max", 0, 3, None, Done),
    Todo(2, "none", 0, 5, None, Pending),
    Todo(4, "late", 0, 1, Some(Due("2026-02-01T00:00")), Pending),
    Todo(3, "early-low", 0, 1, Some(Due("2026-01-01T00:00")), Pending),
    Todo(1, "early-high", 0, 5, Some(Due("2026-01-01T00:00")), Pending),
  ]
  tasks.visible_sorted(values, True)
  |> should.equal([
    Todo(1, "early-high", 0, 5, Some(Due("2026-01-01T00:00")), Pending),
    Todo(2, "none", 0, 5, None, Pending),
    Todo(3, "early-low", 0, 1, Some(Due("2026-01-01T00:00")), Pending),
    Todo(4, "late", 0, 1, Some(Due("2026-02-01T00:00")), Pending),
    Todo(2_147_483_647, "max", 0, 3, None, Done),
  ])
  tasks.visible_sorted(values, False)
  |> should.equal([
    Todo(1, "early-high", 0, 5, Some(Due("2026-01-01T00:00")), Pending),
    Todo(2, "none", 0, 5, None, Pending),
    Todo(3, "early-low", 0, 1, Some(Due("2026-01-01T00:00")), Pending),
    Todo(4, "late", 0, 1, Some(Due("2026-02-01T00:00")), Pending),
  ])
}

pub fn completion_test() {
  let values = [
    Todo(2_147_483_647, "max", 0, 3, None, Done),
    Todo(2, "none", 0, 5, None, Pending),
    Todo(4, "late", 0, 1, Some(Due("2026-02-01T00:00")), Pending),
    Todo(3, "early-low", 0, 1, Some(Due("2026-01-01T00:00")), Pending),
    Todo(1, "early-high", 0, 5, Some(Due("2026-01-01T00:00")), Pending),
  ]
  tasks.complete(values, 2)
  |> should.equal(
    Ok(#(
      [
        Todo(2_147_483_647, "max", 0, 3, None, Done),
        Todo(2, "none", 0, 5, None, Done),
        Todo(4, "late", 0, 1, Some(Due("2026-02-01T00:00")), Pending),
        Todo(3, "early-low", 0, 1, Some(Due("2026-01-01T00:00")), Pending),
        Todo(1, "early-high", 0, 5, Some(Due("2026-01-01T00:00")), Pending),
      ],
      Todo(2, "none", 0, 5, None, Done),
    )),
  )
  tasks.complete(values, 2_147_483_647) |> should.equal(Error(AlreadyDone))
  tasks.complete(values, 20) |> should.equal(Error(NotFound))
}
