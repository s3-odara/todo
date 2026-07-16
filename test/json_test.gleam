import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability
import tasks/domain/due
import tasks/domain/model.{Done, Todo}
import tasks/domain/policy.{Asap}
import tasks/store/json

fn state_json(tasks: String, version: String) -> String {
  "{\"version\":"
  <> version
  <> ",\"tasks\":"
  <> tasks
  <> ",\"availability\":{\"weekly\":[],\"overrides\":[]},\"current_schedule\":null}"
}

pub fn version_one_app_state_round_trip_test() {
  let deadline = due.from_unix_seconds(1_768_173_540)
  let state =
    AppState(
      1,
      [Todo(2, "日本語: # \\\"", 0, 5, Some(deadline), Done, Asap, 45)],
      availability.empty(),
      None,
    )
  json.decode(json.encode(state)) |> should.equal(Ok(state))
}

pub fn tasks_are_encoded_in_canonical_id_order_test() {
  let first = Todo(1, "first", 0, 3, None, Done, Asap, 30)
  let second = Todo(2, "second", 0, 3, None, Done, Asap, 30)
  let encoded =
    json.encode(AppState(1, [second, first], availability.empty(), None))

  encoded
  |> should.equal(
    "{\"version\":1,\"tasks\":[{\"id\":1,\"title\":\"first\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"done\",\"scheduling_policy\":\"asap\",\"minimum_split_minutes\":30},{\"id\":2,\"title\":\"second\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"done\",\"scheduling_policy\":\"asap\",\"minimum_split_minutes\":30}],\"availability\":{\"weekly\":[],\"overrides\":[]},\"current_schedule\":null}",
  )
}

pub fn unknown_version_is_rejected_test() {
  let assert Error(_) = json.decode(state_json("[]", "2"))
}

pub fn duplicate_or_invalid_tasks_are_rejected_test() {
  let valid =
    "{\"id\":1,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"pending\",\"scheduling_policy\":\"spread\",\"minimum_split_minutes\":30}"
  let invalid = [
    "{\"id\":0,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"pending\",\"scheduling_policy\":\"spread\",\"minimum_split_minutes\":30}",
    "{\"id\":1,\"title\":\"x\",\"estimate_minutes\":525601,\"priority\":3,\"due\":null,\"status\":\"pending\",\"scheduling_policy\":\"spread\",\"minimum_split_minutes\":30}",
    "{\"id\":1,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":6,\"due\":null,\"status\":\"pending\",\"scheduling_policy\":\"spread\",\"minimum_split_minutes\":30}",
    "{\"id\":1,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"pending\",\"scheduling_policy\":\"unknown\",\"minimum_split_minutes\":30}",
    "{\"id\":1,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"pending\",\"scheduling_policy\":\"spread\",\"minimum_split_minutes\":0}",
  ]
  invalid
  |> list.each(fn(task) {
    let assert Error(_) = json.decode(state_json("[" <> task <> "]", "1"))
  })
  let assert Error(_) =
    json.decode(state_json("[" <> valid <> "," <> valid <> "]", "1"))
}

pub fn non_null_schedule_is_deferred_and_rejected_in_phase_one_test() {
  let text =
    "{\"version\":1,\"tasks\":[],\"availability\":{\"weekly\":[],\"overrides\":[]},\"current_schedule\":{}}"
  let assert Error(_) = json.decode(text)
}

pub fn malformed_or_incomplete_json_is_rejected_test() {
  let assert Error(_) = json.decode("[")
  let assert Error(_) = json.decode("{\"version\":1}")
}
