import gleam/option.{Some}
import gleeunit/should
import tasks/domain/due
import tasks/domain/model.{Done, Pending, Todo}
import tasks/store/json

pub fn round_trip_test() {
  let deadline = due.from_unix_seconds(1_768_173_540)
  let tasks = [Todo(2, "日本語: # \\\"", 0, 5, Some(deadline), Done)]
  json.decode(json.encode(tasks)) |> should.equal(Ok(tasks))
}

pub fn app_owned_values_are_not_domain_validated_test() {
  let deadline = due.from_unix_seconds(-1)
  json.decode(
    "[{\"id\":-1,\"title\":\"\",\"estimate_minutes\":-2,\"priority\":9,\"due\":-1,\"status\":\"pending\",\"ignored\":true}]",
  )
  |> should.equal(Ok([Todo(-1, "", -2, 9, Some(deadline), Pending)]))
}

pub fn an_unknown_task_status_is_rejected_test() {
  let assert Error(_) =
    json.decode(
      "[{\"id\":1,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"blocked\"}]",
    )
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
