import gleam/list
import gleam/option.{Some}
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{Pending, Todo}
import tasks/domain/policy.{Spread}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/search.{SearchSpace}
import tasks/domain/scheduling/timeline.{AbsoluteInterval}

fn task(estimate, minimum) {
  Todo(
    1,
    "task",
    estimate,
    3,
    Some(due.from_unix_seconds(7200)),
    Pending,
    Spread,
    minimum,
  )
}

fn block(start, end) {
  scheduling_model.ScheduleBlock(
    1,
    timestamp.from_unix_seconds(start),
    timestamp.from_unix_seconds(end),
  )
}

pub fn effective_minimum_split_boundaries_test() {
  model.effective_minimum_split(task(20, 30)) |> should.equal(20)
  model.effective_minimum_split(task(30, 30)) |> should.equal(30)
  model.effective_minimum_split(task(60, 30)) |> should.equal(30)
}

pub fn generation_validator_accepts_short_estimate_exception_test() {
  invariant.validate_generation(
    [block(0, 1200)],
    [task(20, 30)],
    SearchSpace([AbsoluteInterval(0, 3600)], 0, 0),
  )
  |> should.be_ok
}

pub fn generation_validator_rejects_hard_constraint_violations_test() {
  let invalid = [
    [block(-60, 1800)],
    [block(0, 1740)],
    [block(0, 3600), block(1800, 5400)],
    [block(0, 1860)],
  ]
  invalid
  |> list.each(fn(blocks) {
    invariant.validate_generation(
      blocks,
      [task(30, 30)],
      SearchSpace([AbsoluteInterval(0, 3600)], 0, 0),
    )
    |> should.be_error
  })
}

pub fn nanosecond_block_boundaries_are_rejected_test() {
  let nano_block =
    scheduling_model.ScheduleBlock(
      1,
      timestamp.from_unix_seconds_and_nanoseconds(seconds: 0, nanoseconds: 1),
      timestamp.from_unix_seconds_and_nanoseconds(seconds: 1800, nanoseconds: 1),
    )
  invariant.validate_generation(
    [nano_block],
    [task(30, 30)],
    SearchSpace([AbsoluteInterval(0, 3600)], 0, 0),
  )
  |> should.be_error
}

pub fn adjacent_same_task_blocks_are_normalized_test() {
  invariant.canonicalize([block(0, 1800), block(1800, 3600)])
  |> should.equal([block(0, 3600)])
}
