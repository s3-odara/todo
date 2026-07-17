import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/time/calendar
import gleam/time/timestamp
import tasks/domain/app_state.{type AppState, AppState}
import tasks/domain/availability.{
  type Availability, type DateOverride, type Interval, type WeeklyAvailability,
  Availability, DateOverride, Interval, WeeklyAvailability, weekday_number,
  weekday_string,
}
import tasks/domain/due
import tasks/domain/local_time.{type Weekday, Mon}
import tasks/domain/model.{
  type Todo, Pending, Todo, parse_status, status_to_string,
}
import tasks/domain/policy.{Spread}
import tasks/domain/scheduling/invariant as scheduling_invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/validation

pub fn decode(text: String) -> Result(AppState, String) {
  json.parse(from: text, using: state_decoder())
  |> result.map_error(fn(_) { "invalid JSON" })
  |> result.try(validate_state)
}

fn state_decoder() {
  use version <- decode.field("version", decode.int)
  use tasks <- decode.field("tasks", decode.list(of: task_decoder()))
  use availability <- decode.field("availability", availability_decoder())
  use current_schedule <- decode.field(
    "current_schedule",
    decode.optional(schedule_decoder()),
  )
  case version {
    1 -> decode.success(AppState(tasks, availability, current_schedule))
    _ ->
      decode.failure(
        AppState(tasks, availability, current_schedule),
        expected: "version 1 AppState",
      )
  }
}

fn task_decoder() {
  use id <- decode.field("id", decode.int)
  use title <- decode.field("title", decode.string)
  use estimate <- decode.field("estimate_minutes", decode.int)
  use priority <- decode.field("priority", decode.int)
  use due_value <- decode.field(
    "due",
    decode.optional(decode.int |> decode.map(due.from_unix_seconds)),
  )
  use status <- decode.field("status", status_decoder())
  use scheduling_policy <- decode.field("scheduling_policy", policy_decoder())
  use minimum_split <- decode.field("minimum_split_minutes", decode.int)
  case
    validation.persisted_task(
      id,
      title,
      estimate,
      priority,
      due_value,
      status,
      scheduling_policy,
      minimum_split,
    )
  {
    Ok(task) -> decode.success(task)
    Error(_) ->
      decode.failure(
        Todo(1, "invalid", 0, 3, None, Pending, Spread, 30),
        expected: "valid task",
      )
  }
}

fn status_decoder() {
  decode.string
  |> decode.then(fn(value) {
    case parse_status(value) {
      Ok(status) -> decode.success(status)
      Error(_) -> decode.failure(Pending, expected: "task status")
    }
  })
}

fn policy_decoder() {
  decode.string
  |> decode.then(fn(value) {
    case policy.parse(value) {
      Ok(policy) -> decode.success(policy)
      Error(_) -> decode.failure(Spread, expected: "scheduling policy")
    }
  })
}

fn availability_decoder() {
  use weekly <- decode.field(
    "weekly",
    decode.list(of: weekly_availability_decoder()),
  )
  use overrides <- decode.field(
    "overrides",
    decode.list(of: date_override_decoder()),
  )
  decode.success(Availability(weekly, overrides))
}

fn weekly_availability_decoder() {
  use day <- decode.field("day", weekday_decoder())
  use intervals <- decode.field(
    "intervals",
    decode.list(of: interval_decoder()),
  )
  decode.success(WeeklyAvailability(day, intervals))
}

fn date_override_decoder() {
  use raw_date <- decode.field("date", decode.string)
  use intervals <- decode.field(
    "intervals",
    decode.list(of: interval_decoder()),
  )
  case due.parse_date(raw_date) {
    Ok(date) -> decode.success(DateOverride(date, intervals))
    Error(_) ->
      decode.failure(
        DateOverride(calendar.Date(1, calendar.January, 1), intervals),
        expected: "date override",
      )
  }
}

fn interval_decoder() {
  use from <- decode.field("from", decode.int)
  use to <- decode.field("to", decode.int)
  case from >= 0 && from < to && to <= 1440 {
    True -> decode.success(Interval(from, to))
    False -> decode.failure(Interval(0, 1), expected: "availability interval")
  }
}

fn weekday_decoder() {
  decode.string
  |> decode.then(fn(value) {
    case availability.parse_day(value) {
      Ok(day) -> decode.success(day)
      Error(_) -> decode.failure(Mon, expected: "weekday")
    }
  })
}

fn schedule_decoder() {
  use generated_at <- decode.field(
    "generated_at",
    decode.int |> decode.map(timestamp.from_unix_seconds),
  )
  use planning_start <- decode.field(
    "planning_start",
    decode.int |> decode.map(timestamp.from_unix_seconds),
  )
  use utc_offset_seconds <- decode.field("utc_offset_seconds", decode.int)
  use blocks <- decode.field(
    "blocks",
    decode.list(of: schedule_block_decoder()),
  )
  decode.success(scheduling_model.SavedSchedule(
    generated_at,
    planning_start,
    utc_offset_seconds,
    blocks,
  ))
}

fn schedule_block_decoder() {
  use task_id <- decode.field("task_id", decode.int)
  use start <- decode.field("start", decode.int)
  use end <- decode.field("end", decode.int)
  decode.success(scheduling_model.ScheduleBlock(task_id, start, end))
}

fn validate_state(state: AppState) -> Result(AppState, String) {
  let AppState(tasks: tasks, availability: value, current_schedule: schedule) =
    state
  let Availability(weekly, overrides) = value
  case
    unique_ids(tasks, [])
    && unique_weekdays(weekly, [])
    && unique_dates(overrides, [])
    && weekly
    == list.sort(weekly, by: fn(a, b) {
      int.compare(weekday_number(a.day), weekday_number(b.day))
    })
    && overrides
    == list.sort(overrides, by: fn(a, b) {
      calendar.naive_date_compare(a.date, b.date)
    })
    && list.all(weekly, fn(entry) {
      entry.intervals != [] && availability.is_canonical(entry.intervals)
    })
    && list.all(overrides, fn(entry) {
      availability.is_canonical(entry.intervals)
    })
    && valid_schedule(schedule, tasks)
  {
    True -> Ok(state)
    False -> Error("invalid JSON")
  }
}

fn valid_schedule(
  schedule: Option(scheduling_model.SavedSchedule),
  tasks: List(Todo),
) -> Bool {
  case schedule {
    None -> True
    Some(saved) ->
      case
        scheduling_invariant.validate_persisted(
          saved.blocks,
          tasks,
          saved.utc_offset_seconds,
        )
      {
        Ok(_) -> True
        Error(_) -> False
      }
  }
}

fn unique_weekdays(
  entries: List(WeeklyAvailability),
  seen: List(Weekday),
) -> Bool {
  case entries {
    [] -> True
    [entry, ..rest] ->
      case list.contains(seen, entry.day) {
        True -> False
        False -> unique_weekdays(rest, [entry.day, ..seen])
      }
  }
}

fn unique_dates(
  entries: List(DateOverride),
  seen: List(calendar.Date),
) -> Bool {
  case entries {
    [] -> True
    [entry, ..rest] ->
      case list.contains(seen, entry.date) {
        True -> False
        False -> unique_dates(rest, [entry.date, ..seen])
      }
  }
}

fn unique_ids(tasks: List(Todo), seen: List(Int)) -> Bool {
  case tasks {
    [] -> True
    [task, ..rest] ->
      case list.contains(seen, task.id) {
        True -> False
        False -> unique_ids(rest, [task.id, ..seen])
      }
  }
}

pub fn encode(state: AppState) -> String {
  // The version belongs to this storage envelope, not to the domain state.
  let AppState(tasks, availability, current_schedule) = state
  json.object([
    #("version", json.int(1)),
    #(
      "tasks",
      json.array(
        list.sort(tasks, by: fn(a, b) { int.compare(a.id, b.id) }),
        of: task_json,
      ),
    ),
    #("availability", availability_json(availability)),
    #("current_schedule", json.nullable(current_schedule, of: schedule_json)),
  ])
  |> json.to_string
}

fn task_json(task: Todo) -> json.Json {
  json.object([
    #("id", json.int(task.id)),
    #("title", json.string(task.title)),
    #("estimate_minutes", json.int(task.estimate_minutes)),
    #("priority", json.int(task.priority)),
    #("due", json.nullable(task.due, of: due_json)),
    #("status", json.string(status_to_string(task.status))),
    #(
      "scheduling_policy",
      json.string(policy.to_string(task.scheduling_policy)),
    ),
    #("minimum_split_minutes", json.int(task.minimum_split_minutes)),
  ])
}

fn availability_json(value: Availability) -> json.Json {
  let Availability(weekly, overrides) = value
  json.object([
    #(
      "weekly",
      json.array(
        list.sort(weekly, by: fn(a, b) {
          int.compare(weekday_number(a.day), weekday_number(b.day))
        }),
        of: weekly_json,
      ),
    ),
    #(
      "overrides",
      json.array(
        list.sort(overrides, by: fn(a, b) {
          calendar.naive_date_compare(a.date, b.date)
        }),
        of: override_json,
      ),
    ),
  ])
}

fn weekly_json(value: WeeklyAvailability) -> json.Json {
  json.object([
    #("day", json.string(weekday_string(value.day))),
    #("intervals", intervals_json(value.intervals)),
  ])
}

fn override_json(value: DateOverride) -> json.Json {
  json.object([
    #("date", json.string(local_time.format_date(value.date))),
    #("intervals", intervals_json(value.intervals)),
  ])
}

fn intervals_json(values: List(Interval)) -> json.Json {
  json.array(
    list.sort(values, by: fn(a, b) {
      case int.compare(a.from, b.from) {
        order.Eq -> int.compare(a.to, b.to)
        other -> other
      }
    }),
    of: fn(value) {
      json.object([
        #("from", json.int(value.from)),
        #("to", json.int(value.to)),
      ])
    },
  )
}

fn schedule_json(value: scheduling_model.SavedSchedule) -> json.Json {
  json.object([
    #("generated_at", instant_json(value.generated_at)),
    #("planning_start", instant_json(value.planning_start)),
    #("utc_offset_seconds", json.int(value.utc_offset_seconds)),
    #(
      "blocks",
      json.array(
        list.sort(value.blocks, by: fn(a, b) {
          case int.compare(a.start_seconds, b.start_seconds) {
            order.Eq -> int.compare(a.task_id, b.task_id)
            other -> other
          }
        }),
        of: fn(block) {
          json.object([
            #("task_id", json.int(block.task_id)),
            #("start", json.int(block.start_seconds)),
            #("end", json.int(block.end_seconds)),
          ])
        },
      ),
    ),
  ])
}

fn instant_json(value) -> json.Json {
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(value)
  json.int(seconds)
}

fn due_json(value) -> json.Json {
  json.int(due.to_unix_seconds(value))
}
