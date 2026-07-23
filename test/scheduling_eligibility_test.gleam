import gleam/option.{None, Some}
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{Done, Pending, Todo}
import tasks/domain/policy.{Spread}
import tasks/domain/scheduling/eligibility
import tasks/domain/scheduling/model as scheduling_model
import test_support.{id}

pub fn exclusion_precedence_and_stable_order_test() {
  let tasks = [
    Todo(
      id(5),
      "past",
      30,
      3,
      Some(due.from_unix_seconds(0)),
      Pending,
      Spread,
      30,
    ),
    Todo(id(4), "no due", 30, 3, None, Pending, Spread, 30),
    Todo(id(3), "no estimate", 0, 3, None, Pending, Spread, 30),
    Todo(id(2), "done wins", 0, 3, None, Done, Spread, 30),
    Todo(
      id(1),
      "eligible",
      30,
      3,
      Some(due.from_unix_seconds(3600)),
      Pending,
      Spread,
      30,
    ),
  ]
  eligibility.classify(tasks, 0)
  |> should.equal(
    eligibility.Classification(
      [scheduling_model.SchedulingTask(0, 30, 3, 3600, Spread, 30)],
      [
        scheduling_model.ExcludedTask(id(2), scheduling_model.Completed),
        scheduling_model.ExcludedTask(id(3), scheduling_model.MissingEstimate),
        scheduling_model.ExcludedTask(id(4), scheduling_model.MissingDue),
        scheduling_model.ExcludedTask(
          id(5),
          scheduling_model.DeadlineNotAfterStart,
        ),
      ],
      [#(0, id(1))],
    ),
  )
}
