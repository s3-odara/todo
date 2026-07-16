import gleam/float
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{type Todo, Pending, Todo}
import tasks/domain/policy.{Asap, NearDeadline, Spread}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/score

fn task(policy) {
  Todo(1, "task", 60, 3, Some(due.from_unix_seconds(3600)), Pending, policy, 30)
}

fn sampled_task() {
  Todo(1, "task", 60, 3, Some(due.from_unix_seconds(512)), Pending, Spread, 1)
}

fn block(start: Int, end: Int) {
  scheduling_model.ScheduleBlock(
    1,
    timestamp.from_unix_seconds(start),
    timestamp.from_unix_seconds(end),
  )
}

fn reference_policy_error(
  task: Todo,
  blocks: List(scheduling_model.ScheduleBlock),
) -> Float {
  reference_sum(task, blocks, 0, 0.0) /. int.to_float(score.sample_count)
}

fn reference_sum(
  task: Todo,
  blocks: List(scheduling_model.ScheduleBlock),
  k: Int,
  sum: Float,
) -> Float {
  case k >= score.sample_count {
    True -> sum
    False -> {
      let x = { int.to_float(k) +. 0.5 } /. int.to_float(score.sample_count)
      let sample = x *. 512.0
      let worked =
        list.fold(blocks, 0.0, fn(total, current) {
          let start = int.to_float(invariant.seconds(current.start))
          let end = int.to_float(invariant.seconds(current.end))
          case sample <=. start {
            True -> total
            False -> total +. float.min(sample, end) -. start
          }
        })
      let actual = worked /. { int.to_float(task.estimate_minutes) *. 60.0 }
      let difference = actual -. score.policy_value(task.scheduling_policy, x)
      reference_sum(task, blocks, k + 1, sum +. difference *. difference)
    }
  }
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

pub fn chronological_policy_sweep_matches_reference_at_boundaries_test() {
  let current = sampled_task()
  let cases = [
    [],
    // Midpoints are odd seconds: these hit start=1 and end=3 exactly.
    [block(1, 3)],
    [block(3, 9), block(11, 17), block(200, 400)],
    [block(0, 512)],
  ]
  list.each(cases, fn(blocks) {
    score.policy_error(current, blocks, 0)
    |> should.equal(reference_policy_error(current, blocks))
  })
}

pub fn noncanonical_policy_blocks_retain_reference_behavior_test() {
  let current = sampled_task()
  let cases = [
    [block(11, 17), block(3, 9)],
    [block(3, 15), block(9, 17)],
    [block(9, 9)],
  ]
  list.each(cases, fn(blocks) {
    score.policy_error(current, blocks, 0)
    |> should.equal(reference_policy_error(current, blocks))
  })
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
  let blocks = [
    scheduling_model.ScheduleBlock(
      1,
      timestamp.from_unix_seconds(0),
      timestamp.from_unix_seconds(1800),
    ),
  ]
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
