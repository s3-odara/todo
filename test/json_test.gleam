import datebook/weekday.{Friday, Monday}
import gleam/list
import gleam/option.{None, Some}
import gleam/time/calendar.{Date, July}
import gleam/time/timestamp
import gleeunit/should
import tasks/domain/app_state.{AppState}
import tasks/domain/availability
import tasks/domain/due
import tasks/domain/model.{Done, Todo}
import tasks/domain/policy.{Asap}
import tasks/domain/scheduling/model as scheduling_model
import tasks/store/json

fn state_json(tasks: String) -> String {
  "{\"tasks\":"
  <> tasks
  <> ",\"availability\":{\"weekly\":[],\"overrides\":[]},\"current_schedule\":null}"
}

pub fn app_state_round_trip_test() {
  let deadline = due.from_unix_seconds(1_768_173_540)
  let state =
    AppState(
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
    json.encode(AppState([second, first], availability.empty(), None))

  encoded
  |> should.equal(
    "{\"tasks\":[{\"id\":1,\"title\":\"first\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"done\",\"scheduling_policy\":\"asap\",\"minimum_split_minutes\":30},{\"id\":2,\"title\":\"second\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"done\",\"scheduling_policy\":\"asap\",\"minimum_split_minutes\":30}],\"availability\":{\"weekly\":[],\"overrides\":[]},\"current_schedule\":null}",
  )
}

pub fn availability_round_trip_is_canonical_and_preserves_closed_dates_test() {
  let value =
    availability.Availability(
      [
        availability.WeeklyAvailability(Friday, [
          availability.Interval(780, 840),
        ]),
        availability.WeeklyAvailability(Monday, [
          availability.Interval(540, 720),
        ]),
      ],
      [availability.DateOverride(Date(2026, July, 21), [])],
    )
  let encoded = json.encode(AppState([], value, None))
  encoded
  |> should.equal(
    "{\"tasks\":[],\"availability\":{\"weekly\":[{\"day\":\"mon\",\"intervals\":[{\"from\":540,\"to\":720}]},{\"day\":\"fri\",\"intervals\":[{\"from\":780,\"to\":840}]}],\"overrides\":[{\"date\":\"2026-07-21\",\"intervals\":[]}]},\"current_schedule\":null}",
  )
  json.decode(encoded)
  |> should.equal(
    Ok(AppState(
      [],
      availability.Availability(
        [
          availability.WeeklyAvailability(Monday, [
            availability.Interval(540, 720),
          ]),
          availability.WeeklyAvailability(Friday, [
            availability.Interval(780, 840),
          ]),
        ],
        [availability.DateOverride(Date(2026, July, 21), [])],
      ),
      None,
    )),
  )
}

pub fn unknown_task_enums_are_rejected_test() {
  let invalid = [
    "{\"id\":1,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"unknown\",\"scheduling_policy\":\"spread\",\"minimum_split_minutes\":30}",
    "{\"id\":1,\"title\":\"x\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"pending\",\"scheduling_policy\":\"unknown\",\"minimum_split_minutes\":30}",
  ]
  invalid
  |> list.each(fn(task) {
    let assert Error(_) = json.decode(state_json("[" <> task <> "]"))
  })
}

pub fn malformed_non_null_schedule_is_rejected_test() {
  let text =
    "{\"tasks\":[],\"availability\":{\"weekly\":[],\"overrides\":[]},\"current_schedule\":{}}"
  let assert Error(_) = json.decode(text)
}

pub fn persisted_schedule_round_trip_test() {
  let task = Todo(1, "old snapshot", 0, 3, None, Done, Asap, 45)
  let schedule =
    scheduling_model.SavedSchedule(
      timestamp.from_unix_seconds(1),
      timestamp.from_unix_seconds(0),
      0,
      [
        scheduling_model.ScheduleBlock(1, 60, 120),
      ],
    )
  let state = AppState([task], availability.empty(), Some(schedule))
  json.decode(json.encode(state)) |> should.equal(Ok(state))
}

pub fn non_null_schedule_has_byte_exact_canonical_encoding_test() {
  let text =
    "{\"tasks\":[{\"id\":1,\"title\":\"old snapshot\",\"estimate_minutes\":0,\"priority\":3,\"due\":null,\"status\":\"done\",\"scheduling_policy\":\"asap\",\"minimum_split_minutes\":45}],\"availability\":{\"weekly\":[],\"overrides\":[]},\"current_schedule\":{\"generated_at\":1,\"planning_start\":0,\"utc_offset_seconds\":0,\"blocks\":[{\"task_id\":1,\"start\":60,\"end\":120}]}}"
  let assert Ok(value) = json.decode(text)
  json.encode(value) |> should.equal(text)
}

pub fn negative_seconds_non_null_schedule_round_trips_canonical_bytes_test() {
  let text =
    "{\"tasks\":[{\"id\":1,\"title\":\"before epoch\",\"estimate_minutes\":1,\"priority\":3,\"due\":null,\"status\":\"done\",\"scheduling_policy\":\"asap\",\"minimum_split_minutes\":1}],\"availability\":{\"weekly\":[],\"overrides\":[]},\"current_schedule\":{\"generated_at\":-120,\"planning_start\":-60,\"utc_offset_seconds\":0,\"blocks\":[{\"task_id\":1,\"start\":-60,\"end\":0}]}}"
  let assert Ok(value) = json.decode(text)

  json.encode(value) |> should.equal(text)
}

pub fn malformed_or_incomplete_json_is_rejected_test() {
  let assert Error(_) = json.decode("[")
  let assert Error(_) = json.decode("{}")
}
