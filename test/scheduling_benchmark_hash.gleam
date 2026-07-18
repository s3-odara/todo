import gleam/int

const uint32_mask = 4_294_967_295

const seed_salt = 2_654_435_769

// Not H(index + seed): adjacent seeds become shifted copies.
// Hashing the salted seed first gives each seed a different index permutation.
pub fn value(seed: Int, index: Int) -> Int {
  lowbias32(int.bitwise_exclusive_or(index, lowbias32(seed + seed_salt)))
}

pub fn sample(seed: Int, index: Int, bound: Int) -> Int {
  value(seed, index) % bound
}

fn lowbias32(value: Int) -> Int {
  let x = uint32(value)
  let x = uint32(xor_shift_right(x, 16) * 2_146_121_005)
  let x = uint32(xor_shift_right(x, 15) * 2_221_713_035)
  uint32(xor_shift_right(x, 16))
}

fn uint32(value: Int) {
  int.bitwise_and(value, uint32_mask)
}

fn xor_shift_right(value: Int, bits: Int) {
  int.bitwise_exclusive_or(value, int.bitwise_shift_right(value, bits))
}
