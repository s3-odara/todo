import gleam/option.{None}
import gleeunit/should
import tasks/domain/model.{AmbiguousId, Pending, Todo}
import tasks/domain/policy.{Spread}
import tasks/domain/task_id
import tasks/domain/tasks

fn parsed(value) {
  let assert Ok(id) = task_id.parse(value)
  id
}

fn task(id) {
  Todo(id, "task", 0, 3, None, Pending, Spread, 30)
}

pub fn short_ids_are_the_last_eight_hex_digits_test() {
  let first = parsed("00000000-0000-7000-8000-0011deadbeef")
  let second = parsed("00000000-0000-7000-8000-0022deadbeef")
  let other = parsed("00000000-0000-7000-8000-0000cafebabe")

  task_id.short(first) |> should.equal("deadbeef")
  task_id.short(second) |> should.equal("deadbeef")
  task_id.short(other) |> should.equal("cafebabe")
}

pub fn selectors_accept_longer_suffixes_and_reject_ambiguous_ones_test() {
  let first = parsed("00000000-0000-7000-8000-0011deadbeef")
  let second = parsed("00000000-0000-7000-8000-0022deadbeef")
  let todos = [task(first), task(second)]

  tasks.resolve_id(todos, "deadbeef") |> should.equal(Error(AmbiguousId))
  tasks.resolve_id(todos, "1deadbeef") |> should.equal(Ok(first))
  tasks.resolve_id(todos, "2deadbeef") |> should.equal(Ok(second))
}

pub fn only_uuid_v7_is_accepted_as_a_persistent_task_id_test() {
  task_id.parse("00000000-0000-7000-8000-000000000001")
  |> should.be_ok
  task_id.parse("00000000-0000-4000-8000-000000000001")
  |> should.equal(Error(Nil))
}

pub fn generated_ids_are_valid_uuid_v7_values_test() {
  let generated = task_id.generate()
  generated
  |> task_id.to_string
  |> task_id.parse
  |> should.equal(Ok(generated))
}
