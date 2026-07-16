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

fn block(start: Int, end: Int) {
  scheduling_model.ScheduleBlock(
    1,
    timestamp.from_unix_seconds(start),
    timestamp.from_unix_seconds(end),
  )
}

fn other_task_block(start: Int, end: Int) {
  scheduling_model.ScheduleBlock(
    2,
    timestamp.from_unix_seconds(start),
    timestamp.from_unix_seconds(end),
  )
}

fn close(actual: Float, expected: Float) {
  let is_close = float.absolute_value(actual -. expected) <. 0.00000000001
  is_close |> should.be_true
}

pub fn policy_curves_and_empty_progress_integrals_test() {
  score.policy_value(Asap, 0.5) |> should.equal(0.75)
  score.policy_value(Spread, 0.5) |> should.equal(0.5)
  score.policy_value(NearDeadline, 0.5) |> should.equal(0.25)

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

pub fn arbitrary_blocks_are_clipped_sorted_and_union_merged_test() {
  let canonical_union = [block(0, 1800), block(2700, 3600)]
  let arbitrary = [
    other_task_block(0, 3600),
    block(2700, 4000),
    block(900, 1800),
    block(-600, 1200),
    block(600, 1500),
    block(2500, 2500),
    block(2000, 1900),
  ]
  let exact = score.policy_error(task(Asap), arbitrary, 0)
  close(exact, score.policy_error(task(Asap), canonical_union, 0))
  let reference =
    dense_midpoint_reference(task(Asap), canonical_union, 0, 20_000)
  let agrees_with_dense_reference =
    float.absolute_value(exact -. reference) <. 0.00000001
  agrees_with_dense_reference |> should.be_true
}

pub fn boundaries_and_invalid_windows_are_safe_test() {
  // Wholly outside and zero/negative blocks contribute no progress.
  close(
    score.policy_error(
      task(NearDeadline),
      [block(-100, 0), block(3600, 4000), block(5, 5), block(10, 9)],
      0,
    ),
    1.0 /. 5.0,
  )
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
  score.policy_error(no_span, [block(-100, 100)], 0) |> should.equal(0.0)
  score.policy_error(task(Spread), [block(0, 3600)], 3600)
  |> should.equal(0.0)
}

fn dense_midpoint_reference(
  current: Todo,
  union_blocks: List(scheduling_model.ScheduleBlock),
  planning_start: Int,
  count: Int,
) -> Float {
  let assert Some(deadline) = current.due
  let span = int.to_float(due.to_unix_seconds(deadline) - planning_start)
  dense_sum(current, union_blocks, planning_start, span, count, 0, 0.0)
  /. int.to_float(count)
}

fn dense_sum(
  current: Todo,
  blocks: List(scheduling_model.ScheduleBlock),
  planning_start: Int,
  span: Float,
  count: Int,
  index: Int,
  total: Float,
) -> Float {
  case index >= count {
    True -> total
    False -> {
      let x = { int.to_float(index) +. 0.5 } /. int.to_float(count)
      let sample = int.to_float(planning_start) +. x *. span
      let worked =
        list.fold(blocks, 0.0, fn(acc, current) {
          let start = int.to_float(invariant.seconds(current.start))
          let end = int.to_float(invariant.seconds(current.end))
          acc +. float.max(0.0, float.min(sample, end) -. start)
        })
      let actual = worked /. { int.to_float(current.estimate_minutes) *. 60.0 }
      let difference =
        actual -. score.policy_value(current.scheduling_policy, x)
      dense_sum(
        current,
        blocks,
        planning_start,
        span,
        count,
        index + 1,
        total +. difference *. difference,
      )
    }
  }
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
