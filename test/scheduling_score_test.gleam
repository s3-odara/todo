import gleam/float
import gleam/option.{Some}
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score

fn task(policy) {
  Todo(1, "task", 60, 3, Some(due.from_unix_seconds(3600)), Pending, policy, 30)
}

pub fn policy_curves_and_midpoint_sampling_test() {
  score.policy_value(Asap, 0.5) |> should.equal(0.75)
  score.policy_value(Spread, 0.5) |> should.equal(0.5)
  score.policy_value(NearDeadline, 0.5) |> should.equal(0.25)
  let error = score.policy_error(task(Spread), [], 0)
  let close =
    float.absolute_value(error -. 0.3333320617675781) <. 0.000000000001
  close |> should.be_true
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
  let block =
    scheduling_model.ScheduleBlock(
      1,
      timestamp.from_unix_seconds(0),
      timestamp.from_unix_seconds(3600),
    )
  let value = score.evaluate([task(Spread)], [block], 0)
  value.weighted_unscheduled_minutes |> should.equal(0)
  score.priority_weight(5) |> should.equal(16)
  let close = value.weighted_policy_error <. 0.000000000001
  close |> should.be_true
}
