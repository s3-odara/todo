import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{
  AlreadyDone, Done, Due, InvalidDue, InvalidEstimate, InvalidId,
  InvalidPriority, InvalidTitle, NotFound, Pending, Todo,
}
import tasks/domain/tasks
import tasks/domain/validation

pub fn title_boundaries_and_controls_test() {
  validation.title(" clean ") |> should.equal(Ok("clean"))
  validation.title("") |> should.equal(Error(InvalidTitle))
  validation.title("   ") |> should.equal(Error(InvalidTitle))
  validation.title("\tclean") |> should.equal(Error(InvalidTitle))
  validation.title("clean\n") |> should.equal(Error(InvalidTitle))
  validation.title("clean\r") |> should.equal(Error(InvalidTitle))
  validation.title("clean\u{0}") |> should.equal(Error(InvalidTitle))
  validation.title("a") |> should.equal(Ok("a"))
  validation.title(string.repeat("a", 200))
  |> should.equal(Ok(string.repeat("a", 200)))
  validation.title(string.repeat("a", 201)) |> should.equal(Error(InvalidTitle))
}

pub fn estimate_priority_and_id_matrix_test() {
  validation.estimate("0m") |> should.equal(Ok(0))
  validation.estimate("0h") |> should.equal(Ok(0))
  validation.estimate("8760h") |> should.equal(Ok(525_600))
  validation.estimate("525600m") |> should.equal(Ok(525_600))
  validation.estimate("525601m") |> should.equal(Error(InvalidEstimate))
  validation.estimate("8761h") |> should.equal(Error(InvalidEstimate))
  validation.estimate("01m") |> should.equal(Error(InvalidEstimate))
  validation.estimate("1h30m") |> should.equal(Error(InvalidEstimate))
  validation.estimate("1.5h") |> should.equal(Error(InvalidEstimate))
  validation.estimate("3H") |> should.equal(Error(InvalidEstimate))
  validation.estimate("-1m") |> should.equal(Error(InvalidEstimate))
  validation.estimate("1") |> should.equal(Error(InvalidEstimate))
  validation.priority("1") |> should.equal(Ok(1))
  validation.priority("5") |> should.equal(Ok(5))
  validation.priority("0") |> should.equal(Error(InvalidPriority))
  validation.priority("6") |> should.equal(Error(InvalidPriority))
  validation.priority("01") |> should.equal(Error(InvalidPriority))
  validation.priority("x") |> should.equal(Error(InvalidPriority))
  validation.id("1") |> should.equal(Ok(1))
  validation.id("2147483648") |> should.equal(Ok(2_147_483_648))
  validation.id("0") |> should.equal(Error(InvalidId))
  validation.id("01") |> should.equal(Error(InvalidId))
  validation.id("1x") |> should.equal(Error(InvalidId))
}

pub fn due_calendar_and_rejection_matrix_test() {
  due.input("2024-02-29") |> should.equal(Ok(Due("2024-02-29T23:59")))
  due.input("2023-02-29") |> should.equal(Error(InvalidDue))
  due.input("2026-04-31") |> should.equal(Error(InvalidDue))
  due.input("2026-12-31T23:59") |> should.equal(Ok(Due("2026-12-31T23:59")))
  due.input("2026-01-01T24:00") |> should.equal(Error(InvalidDue))
  due.input("2026-01-01T12:60") |> should.equal(Error(InvalidDue))
  due.input("2026-01-01T12:00Z") |> should.equal(Error(InvalidDue))
  due.input("2026-01-01T12:00+09:00") |> should.equal(Error(InvalidDue))
  due.input("2026-01-01T12:00:01") |> should.equal(Error(InvalidDue))
  due.input("2026-01-01T12:00.1") |> should.equal(Error(InvalidDue))
  due.input("2026-01-01t12:00") |> should.equal(Error(InvalidDue))
  due.input("2026-01-01 12:00") |> should.equal(Error(InvalidDue))
}

pub fn sorts_by_id_ascending_test() {
  let due = Some(Due("2026-03-01T12:00"))
  let lower = Todo(8, "lower", 0, 2, due, Pending)
  let higher = Todo(9, "higher", 0, 2, due, Pending)
  tasks.visible_sorted([higher, lower], True) |> should.equal([lower, higher])
}

pub fn ids_completion_and_sort_test() {
  let values = [
    Todo(2_147_483_647, "max", 0, 3, None, Done),
    Todo(2, "none", 0, 5, None, Pending),
    Todo(4, "late", 0, 1, Some(Due("2026-02-01T00:00")), Pending),
    Todo(3, "early-low", 0, 1, Some(Due("2026-01-01T00:00")), Pending),
    Todo(1, "early-high", 0, 5, Some(Due("2026-01-01T00:00")), Pending),
  ]
  tasks.next_id(values) |> should.equal(2_147_483_648)
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
