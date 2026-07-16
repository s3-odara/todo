import gleam/list
import gleam/option.{Some}
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{Pending, Todo}
import tasks/domain/policy.{Spread}
import tasks/domain/scheduling/neighborhood

fn task(id) {
  Todo(id, "task", 1, 1, Some(due.from_unix_seconds(60)), Pending, Spread, 1)
}

fn ids(values) {
  list.map(values, fn(value) {
    neighborhood.tasks(value) |> list.map(fn(item) { item.id })
  })
}

pub fn neighborhood_order_and_small_budgets_test() {
  neighborhood.generate([], 20) |> should.equal([])
  ids(neighborhood.generate([task(2), task(1)], 0)) |> should.equal([])
  ids(neighborhood.generate([task(2), task(1)], 1)) |> should.equal([[1]])
  ids(neighborhood.generate([task(2), task(1)], 4))
  |> should.equal([[1], [2], [1, 2], [2, 1]])

  let three = [task(3), task(1), task(2)]
  ids(neighborhood.generate(three, 8))
  |> should.equal([
    [1],
    [2],
    [3],
    [1, 2],
    [2, 1],
    [1, 3],
    [3, 1],
    [2, 3],
  ])
  ids(neighborhood.generate(three, 10))
  |> should.equal([
    [1],
    [2],
    [3],
    [1, 2],
    [2, 1],
    [1, 3],
    [3, 1],
    [2, 3],
    [3, 2],
    [1, 2, 3],
  ])
  ids(neighborhood.generate(three, 15))
  |> should.equal([
    [1],
    [2],
    [3],
    [1, 2],
    [2, 1],
    [1, 3],
    [3, 1],
    [2, 3],
    [3, 2],
    [1, 2, 3],
    [1, 3, 2],
    [2, 1, 3],
    [2, 3, 1],
    [3, 1, 2],
    [3, 2, 1],
  ])
}

fn tasks_up_to(current, last, acc) {
  case current > last {
    True -> list.reverse(acc)
    False -> tasks_up_to(current + 1, last, [task(current), ..acc])
  }
}

pub fn neighborhood_global_limit_has_literal_boundary_test() {
  let values = tasks_up_to(1, 100, [])
  let generated = neighborhood.generate(values, 20_000)
  list.length(generated) |> should.equal(20_000)
  let assert Ok(last) = list.last(generated)
  ids([last]) |> should.equal([[20, 76, 1]])
}
