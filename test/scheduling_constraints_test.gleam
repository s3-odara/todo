import gleam/list
import gleeunit/should
import tasks/domain/policy.{Spread}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/timeline.{AbsoluteInterval, SearchSpace}

fn scheduling_task(estimate, minimum) {
  scheduling_model.SchedulingTask(1, estimate, 3, 7200, Spread, minimum)
}

fn block(start, end) {
  scheduling_model.ScheduleBlock(1, start, end)
}

pub fn effective_minimum_split_boundaries_test() {
  scheduling_model.effective_minimum_split(scheduling_task(20, 30))
  |> should.equal(20)
  scheduling_model.effective_minimum_split(scheduling_task(30, 30))
  |> should.equal(30)
  scheduling_model.effective_minimum_split(scheduling_task(60, 30))
  |> should.equal(30)
}

pub fn generation_validator_accepts_short_estimate_exception_test() {
  invariant.validate_generation(
    [block(0, 1200)],
    [scheduling_task(20, 30)],
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
      [scheduling_task(30, 30)],
      SearchSpace([AbsoluteInterval(0, 3600)], 0, 0),
    )
    |> should.be_error
  })
}

pub fn adjacent_same_task_blocks_are_normalized_test() {
  invariant.canonicalize([block(0, 1800), block(1800, 3600)])
  |> should.equal([block(0, 3600)])
}

pub fn canonical_insertion_orders_and_merges_blocks_test() {
  invariant.insert_canonical(
    [scheduling_model.ScheduleBlock(2, 600, 1200)],
    scheduling_model.ScheduleBlock(1, 0, 600),
  )
  |> should.equal([
    scheduling_model.ScheduleBlock(1, 0, 600),
    scheduling_model.ScheduleBlock(2, 600, 1200),
  ])

  invariant.insert_canonical(
    [
      scheduling_model.ScheduleBlock(2, 0, 600),
      scheduling_model.ScheduleBlock(2, 1200, 1800),
    ],
    scheduling_model.ScheduleBlock(1, 600, 1200),
  )
  |> should.equal([
    scheduling_model.ScheduleBlock(2, 0, 600),
    scheduling_model.ScheduleBlock(1, 600, 1200),
    scheduling_model.ScheduleBlock(2, 1200, 1800),
  ])

  invariant.insert_canonical(
    [block(0, 600), block(1200, 1800)],
    block(600, 1200),
  )
  |> should.equal([block(0, 1800)])
}
