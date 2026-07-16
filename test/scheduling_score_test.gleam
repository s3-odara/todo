import gleam/float
import gleam/list
import gleam/option.{Some}
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score

fn task(policy) {
  Todo(1, "task", 60, 3, Some(due.from_unix_seconds(3600)), Pending, policy, 30)
}

fn block(start: Int, end: Int) {
  scheduling_model.ScheduleBlock(1, start, end)
}

fn close(actual: Float, expected: Float) {
  let is_close = float.absolute_value(actual -. expected) <. 0.00000000001
  is_close |> should.be_true
}

pub fn policy_curves_and_empty_progress_integrals_test() {
  policy.value(Asap, 0.0) |> should.equal(0.0)
  policy.value(Asap, 0.5) |> should.equal(0.75)
  policy.value(Asap, 1.0) |> should.equal(1.0)
  policy.value(Spread, 0.0) |> should.equal(0.0)
  policy.value(Spread, 0.5) |> should.equal(0.5)
  policy.value(Spread, 1.0) |> should.equal(1.0)
  policy.value(NearDeadline, 0.0) |> should.equal(0.0)
  policy.value(NearDeadline, 0.5) |> should.equal(0.25)
  policy.value(NearDeadline, 1.0) |> should.equal(1.0)

  policy.inverse(Asap, 0.0) |> should.equal(0.0)
  policy.inverse(Asap, 1.0) |> should.equal(1.0)
  close(policy.inverse(Asap, 0.5), 0.2928932188134524)
  policy.inverse(Spread, 0.5) |> should.equal(0.5)
  close(policy.inverse(NearDeadline, 0.5), 0.7071067811865476)
  policy.inverse(NearDeadline, 1.0) |> should.equal(1.0)
  [Asap, Spread, NearDeadline]
  |> list.each(fn(value) {
    policy.inverse(value, -0.5) |> should.equal(0.0)
    policy.inverse(value, 1.5) |> should.equal(1.0)
  })

  close(score.policy_error(task(Asap), [], 0), 8.0 /. 15.0)
  close(score.policy_error(task(Spread), [], 0), 1.0 /. 3.0)
  close(score.policy_error(task(NearDeadline), [], 0), 1.0 /. 5.0)
}

pub fn full_span_progress_integrals_test() {
  let full = [block(0, 3600)]
  close(score.policy_error(task(Asap), full, 0), 1.0 /. 30.0)
  close(score.policy_error(task(Spread), full, 0), 0.0)
  close(score.policy_error(task(NearDeadline), full, 0), 1.0 /. 30.0)
}

pub fn partial_block_and_gap_have_exact_piecewise_error_test() {
  // Actual progress is x through x=1/2 and then remains 1/2.
  close(score.policy_error(task(Spread), [block(0, 1800)], 0), 1.0 /. 24.0)

  // Touching blocks are separate valid segments but describe full-span progress.
  close(
    score.policy_error(
      task(Spread),
      [block(0, 1200), block(1200, 2400), block(2400, 3600)],
      0,
    ),
    0.0,
  )
}

pub fn invalid_planning_windows_return_zero_test() {
  let no_span =
    Todo(
      1,
      "no span",
      60,
      3,
      Some(due.from_unix_seconds(0)),
      Pending,
      Spread,
      30,
    )
  score.policy_error(no_span, [], 0) |> should.equal(0.0)
  score.policy_error(task(Spread), [block(0, 3600)], 3600)
  |> should.equal(0.0)
}

pub fn score_is_lexicographic_with_fixed_epsilon_test() {
  score.compare(
    scheduling_model.Score(1, 0.0),
    scheduling_model.Score(2, -100.0),
  )
  |> should.equal(score.Better)
  score.compare(
    scheduling_model.Score(1, 1.0),
    scheduling_model.Score(1, 1.0 +. score.epsilon /. 2.0),
  )
  |> should.equal(score.Equal)
}

pub fn block_progress_and_priority_weight_test() {
  let value = score.evaluate([task(Spread)], [block(0, 3600)], 0)
  value.weighted_unscheduled_minutes |> should.equal(0)
  score.priority_weight(5) |> should.equal(16)
  close(value.weighted_policy_error, 0.0)
}

pub fn task_contributions_preserve_total_and_ordered_replacement_test() {
  let first = task(Spread)
  let second =
    Todo(
      2,
      "second",
      30,
      5,
      Some(due.from_unix_seconds(3600)),
      Pending,
      Asap,
      30,
    )
  let blocks = [block(0, 1800)]
  let contributions = score.contributions([first, second], blocks, 0)
  score.total(contributions)
  |> should.equal(score.evaluate([first, second], blocks, 0))

  let replacement = score.Contribution(2, scheduling_model.Score(0, 0.25))
  score.replace_contributions(contributions, [replacement])
  |> should.equal([
    score.Contribution(1, score.evaluate_task(first, blocks, 0)),
    replacement,
  ])
}
