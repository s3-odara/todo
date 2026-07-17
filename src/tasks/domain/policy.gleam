import gleam/float

pub type SchedulingPolicy {
  Asap
  Spread
  NearDeadline
}

pub fn value(policy: SchedulingPolicy, x: Float) -> Float {
  case policy {
    Asap -> 1.0 -. { 1.0 -. x } *. { 1.0 -. x }
    Spread -> x
    NearDeadline -> x *. x
  }
}

pub fn inverse(policy: SchedulingPolicy, y: Float) -> Float {
  let bounded = float.max(0.0, float.min(1.0, y))
  case policy {
    Asap ->
      case float.square_root(1.0 -. bounded) {
        Ok(root) -> 1.0 -. root
        Error(_) -> 0.0
      }
    Spread -> bounded
    NearDeadline ->
      case float.square_root(bounded) {
        Ok(root) -> root
        Error(_) -> 0.0
      }
  }
}

pub fn parse(value: String) -> Result(SchedulingPolicy, Nil) {
  case value {
    "asap" -> Ok(Asap)
    "spread" -> Ok(Spread)
    "near_deadline" -> Ok(NearDeadline)
    _ -> Error(Nil)
  }
}

pub fn to_string(policy: SchedulingPolicy) -> String {
  case policy {
    Asap -> "asap"
    Spread -> "spread"
    NearDeadline -> "near_deadline"
  }
}
