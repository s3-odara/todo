import gleam/option.{None, Some}
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{Done, Pending, Todo}
import tasks/domain/policy.{Spread}
import tasks/domain/scheduling/eligibility
import tasks/domain/scheduling/model as scheduling_model

pub fn exclusion_precedence_and_stable_order_test() {
  let tasks = [
    Todo(5, "past", 30, 3, Some(due.from_unix_seconds(0)), Pending, Spread, 30),
    Todo(4, "no due", 30, 3, None, Pending, Spread, 30),
    Todo(3, "no estimate", 0, 3, None, Pending, Spread, 30),
    Todo(2, "done wins", 0, 3, None, Done, Spread, 30),
    Todo(
      1,
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
      [scheduling_model.SchedulingTask(1, 30, 3, 3600, Spread, 30)],
      [
        scheduling_model.ExcludedTask(2, scheduling_model.Completed),
        scheduling_model.ExcludedTask(3, scheduling_model.MissingEstimate),
        scheduling_model.ExcludedTask(4, scheduling_model.MissingDue),
        scheduling_model.ExcludedTask(5, scheduling_model.DeadlineNotAfterStart),
      ],
    ),
  )
}
