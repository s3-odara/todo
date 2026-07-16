pub type SchedulingPolicy {
  Asap
  Spread
  NearDeadline
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
