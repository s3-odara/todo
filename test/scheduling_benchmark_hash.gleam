import gleam/int

const uint32_mask = 4_294_967_295

/// A deterministic lowbias32-based key for benchmark sampling and permutations.
pub fn value(seed: Int, index: Int) -> Int {
  let x = uint32(seed * 2_654_435_761 + index * 2_246_822_507)
  let x = uint32(xor_shift_right(x, 16) * 2_146_121_005)
  let x = uint32(xor_shift_right(x, 15) * 2_221_713_035)
  uint32(xor_shift_right(x, 16))
}

/// Sample a bounded value after avalanche so small bounds avoid arithmetic cycles.
pub fn sample(seed: Int, index: Int, bound: Int) -> Int {
  value(seed, index) % bound
}

fn uint32(value: Int) {
  int.bitwise_and(value, uint32_mask)
}

fn xor_shift_right(value: Int, bits: Int) {
  int.bitwise_exclusive_or(value, int.bitwise_shift_right(value, bits))
}
