import gleam/int
import gleam/list
import gleam/string

/// Parse a non-empty sequence of ASCII decimal digits.
/// Callers retain responsibility for leading-zero and range rules.
pub fn parse_digits(values: List(String)) -> Result(Int, Nil) {
  case digits(values) {
    True -> values |> string.concat |> int.parse
    False -> Error(Nil)
  }
}

pub fn digits(values: List(String)) -> Bool {
  values != [] && list.all(values, is_digit)
}

fn is_digit(value: String) -> Bool {
  case value {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}
