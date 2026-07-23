import gleam/list
import gleeunit/should
import tasks/domain/scheduling/deterministic_rng

pub fn same_seed_returns_same_stream_test() {
  let first = rng_values(20, deterministic_rng.new(101), [])
  let repeat = rng_values(20, deterministic_rng.new(101), [])
  first |> should.equal(repeat)
}

pub fn representative_different_seeds_diverge_test() {
  let #(first, _) = deterministic_rng.next(deterministic_rng.new(101))
  let #(different, _) = deterministic_rng.next(deterministic_rng.new(102))
  first |> should.not_equal(different)
}

pub fn bounded_indexes_stay_in_range_test() {
  let values = rng_values(2000, deterministic_rng.new(41), [])
  list.all(values, fn(value) { value >= 0 && value < 7 })
  |> should.be_true
}

pub fn single_digit_boundary_preserves_compatibility_value_test() {
  // This literal is intentional: the RNG documents this stream as compatible.
  let bound = 2_147_483_646
  let #(value, _) = deterministic_rng.index(deterministic_rng.new(41), bound)
  value |> should.equal(2_027_381)
}

pub fn indexes_support_bounds_larger_than_one_rng_digit_test() {
  let bounds = [
    2_147_483_647,
    4_611_686_009_837_453_317,
  ]
  list.each(bounds, fn(bound) {
    let #(value, _) = deterministic_rng.index(deterministic_rng.new(41), bound)
    let in_range = value >= 0 && value < bound
    in_range |> should.be_true
  })
}

fn rng_values(remaining, rng, acc) {
  case remaining <= 0 {
    True -> acc
    False -> {
      let #(value, rng) = deterministic_rng.index(rng, 7)
      rng_values(remaining - 1, rng, [value, ..acc])
    }
  }
}
