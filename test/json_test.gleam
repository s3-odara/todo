import gleam/option.{Some}
import gleeunit/should
import tasks/domain/model.{Done, Due, Pending, Todo}
import tasks/store/json

pub fn round_trip_test() {
  let tasks = [
    Todo(2, "日本語: # \\\"", 0, 5, Some(Due("2026-07-15T23:59")), Done),
  ]
  json.decode(json.encode(tasks)) |> should.equal(Ok(tasks))
  json.encode([]) |> should.equal("[]")
}

pub fn app_owned_values_are_not_domain_validated_test() {
  json.decode(
    "[{\"id\":-1,\"title\":\"\",\"estimate_minutes\":-2,\"priority\":9,\"due\":\"not-a-date\",\"status\":\"pending\",\"ignored\":true}]",
  )
  |> should.equal(Ok([Todo(-1, "", -2, 9, Some(Due("not-a-date")), Pending)]))
}

pub fn malformed_or_incomplete_json_is_rejected_test() {
  let assert Error(_) = json.decode("[")
  let assert Error(_) =
    json.decode(
      "[{\"id\":1,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null}]",
    )
  let assert Error(_) =
    json.decode(
      "[{\"id\":\"1\",\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"pending\"}]",
    )
}
