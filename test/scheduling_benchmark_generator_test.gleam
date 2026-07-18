import gleam/int
import gleam/list
import gleeunit/should
import scheduling_benchmark_hash

pub fn seeded_lowbias32_is_stable_test() {
  scheduling_benchmark_hash.value(101, 307)
  |> should.equal(1_192_176_205)
}

pub fn generated_profiles_cover_every_categorical_value_test() {
  let seeds = [101, 211, 307, 401, 503, 9001, 9011, 9029, 9041, 9059]

  let indexes = integers(1, 129)
  observed(seeds, indexes, 11, 2, 5) |> should.equal([0, 1, 2, 3, 4])
  observed(seeds, indexes, 11, 3, 4) |> should.equal([0, 1, 2, 3])
  observed(seeds, indexes, 11, 3, 3) |> should.equal([0, 1, 2])
  observed(seeds, indexes, 11, 4, 3) |> should.equal([0, 1, 2])
}

pub fn seed_changes_generated_sequence_test() {
  let indexes = integers(1, 129)
  let first = sampled_sequence(101, indexes, 11, 2, 5)
  let second = sampled_sequence(211, indexes, 11, 2, 5)

  first |> should.not_equal(second)
}

pub fn exact_profiles_cover_every_categorical_value_test() {
  let seeds = integers(1, 31)
  let task_ids = integers(1, 4)

  observed(seeds, task_ids, 17, 0, 4) |> should.equal([0, 1, 2, 3])
  observed(seeds, task_ids, 17, 1, 5) |> should.equal([0, 1, 2, 3, 4])
  observed(seeds, task_ids, 17, 2, 6) |> should.equal([0, 1, 2, 3, 4, 5])
  observed(seeds, task_ids, 17, 3, 2) |> should.equal([0, 1])
  observed(seeds, task_ids, 17, 4, 3) |> should.equal([0, 1, 2])
}

fn observed(
  seeds: List(Int),
  indexes: List(Int),
  multiplier: Int,
  offset: Int,
  bound: Int,
) {
  seeds
  |> list.flat_map(fn(seed) {
    sampled_sequence(seed, indexes, multiplier, offset, bound)
  })
  |> list.sort(by: int.compare)
  |> list.unique
}

fn sampled_sequence(
  seed: Int,
  indexes: List(Int),
  multiplier: Int,
  offset: Int,
  bound: Int,
) {
  indexes
  |> list.map(fn(index) {
    scheduling_benchmark_hash.sample(seed, index * multiplier + offset, bound)
  })
}

fn integers(start: Int, stop: Int) {
  int.range(from: start, to: stop, with: [], run: fn(values, value) {
    [value, ..values]
  })
}
