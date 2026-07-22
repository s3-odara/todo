import gleam/int

const modulus = 2_147_483_647

const multiplier = 48_271

pub opaque type Rng {
  Rng(state: Int)
}

/// Explicit deterministic RNG. There is no clock or process-global entropy.
pub fn new(seed: Int) -> Rng {
  Rng(int.absolute_value(seed) % { modulus - 1 } + 1)
}

pub fn next(rng: Rng) -> #(Int, Rng) {
  let value = { rng.state * multiplier } % modulus
  #(value, Rng(value))
}

/// Uniform integer in [0, bound), using rejection rather than modulo folding.
/// Bounds larger than one RNG digit are sampled from enough base-2,147,483,646
/// digits to cover the bound. The single-digit path is retained verbatim for
/// compatibility with existing deterministic streams.
pub fn index(rng: Rng, bound: Int) -> #(Int, Rng) {
  let #(value, next_rng) = next(rng)
  case bound <= 1 {
    True -> #(0, next_rng)
    False -> {
      let domain = modulus - 1
      let zero_based = value - 1
      case bound <= domain {
        True -> {
          let limit = domain - { domain % bound }
          case zero_based < limit {
            True -> #(zero_based % bound, next_rng)
            False -> index(next_rng, bound)
          }
        }
        False -> expanded_index(next_rng, bound, zero_based, domain)
      }
    }
  }
}

fn expanded_index(rng: Rng, bound: Int, sample: Int, sample_domain: Int) {
  case sample_domain >= bound {
    True -> {
      let limit = sample_domain - { sample_domain % bound }
      case sample < limit {
        True -> #(sample % bound, rng)
        False -> index(rng, bound)
      }
    }
    False -> {
      let #(value, next_rng) = next(rng)
      let domain = modulus - 1
      expanded_index(
        next_rng,
        bound,
        sample * domain + value - 1,
        sample_domain * domain,
      )
    }
  }
}

pub fn uniform(rng: Rng) -> #(Float, Rng) {
  let #(value, next_rng) = next(rng)
  #(int.to_float(value - 1) /. int.to_float(modulus - 1), next_rng)
}
