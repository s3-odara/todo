import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import tasks/domain/app_state.{type AppState, AppState}
import tasks/domain/availability.{
  type Availability, type DateOverride, type Interval, type Weekday,
  type WeeklyAvailability, Availability, DateOverride, Fri, Interval, Mon, Sat,
  Sun, Thu, Tue, Wed, WeeklyAvailability,
}
import tasks/domain/due
import tasks/domain/model.{type Status, type Todo, Done, Pending, Todo}
import tasks/domain/policy.{type SchedulingPolicy, Asap, NearDeadline, Spread}
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/validation

pub fn decode(text: String) -> Result(AppState, String) {
  json.parse(from: text, using: state_decoder())
  |> result.map_error(fn(_) { "invalid JSON" })
  |> result.try(validate_unique_task_ids)
}

fn state_decoder() {
  use version <- decode.field("version", decode.int)
  use tasks <- decode.field("tasks", decode.list(of: task_decoder()))
  use availability <- decode.field("availability", availability_decoder())
  use current_schedule <- decode.field(
    "current_schedule",
    decode.optional(decode.dynamic),
  )
  case version, current_schedule {
    1, None -> decode.success(AppState(1, tasks, availability, None))
    _, _ ->
      decode.failure(
        AppState(1, tasks, availability, None),
        expected: "version 1 AppState with a null current_schedule",
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
    case value {
      "pending" -> decode.success(Pending)
      "done" -> decode.success(Done)
      _ -> decode.failure(Pending, expected: "task status")
    }
  })
}

fn policy_decoder() {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "asap" -> decode.success(Asap)
      "spread" -> decode.success(Spread)
      "near_deadline" -> decode.success(NearDeadline)
      _ -> decode.failure(Spread, expected: "scheduling policy")
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
    case value {
      "mon" -> decode.success(Mon)
      "tue" -> decode.success(Tue)
      "wed" -> decode.success(Wed)
      "thu" -> decode.success(Thu)
      "fri" -> decode.success(Fri)
      "sat" -> decode.success(Sat)
      "sun" -> decode.success(Sun)
      _ -> decode.failure(Mon, expected: "weekday")
    }
  })
}

fn validate_unique_task_ids(state: AppState) -> Result(AppState, String) {
  let AppState(tasks: tasks, ..) = state
  case unique_ids(tasks, []) {
    True -> Ok(state)
    False -> Error("invalid JSON")
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
  let AppState(_, tasks, availability, current_schedule) = state
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
    #("status", json.string(status_string(task.status))),
    #("scheduling_policy", json.string(policy_string(task.scheduling_policy))),
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
    #("date", json.string(date_string(value.date))),
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
          case timestamp.compare(a.start, b.start) {
            order.Eq -> int.compare(a.task_id, b.task_id)
            other -> other
          }
        }),
        of: fn(block) {
          json.object([
            #("task_id", json.int(block.task_id)),
            #("start", instant_json(block.start)),
            #("end", instant_json(block.end)),
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

fn status_string(status: Status) -> String {
  case status {
    Pending -> "pending"
    Done -> "done"
  }
}

fn policy_string(policy: SchedulingPolicy) -> String {
  case policy {
    Asap -> "asap"
    Spread -> "spread"
    NearDeadline -> "near_deadline"
  }
}

fn weekday_number(day: Weekday) -> Int {
  case day {
    Mon -> 1
    Tue -> 2
    Wed -> 3
    Thu -> 4
    Fri -> 5
    Sat -> 6
    Sun -> 7
  }
}

fn weekday_string(day: Weekday) -> String {
  case day {
    Mon -> "mon"
    Tue -> "tue"
    Wed -> "wed"
    Thu -> "thu"
    Fri -> "fri"
    Sat -> "sat"
    Sun -> "sun"
  }
}

fn date_string(date: calendar.Date) -> String {
  date.year
  |> int.to_string
  |> string.pad_start(4, "0")
  |> string.append("-")
  |> string.append(
    date.month
    |> calendar.month_to_int
    |> int.to_string
    |> string.pad_start(2, "0"),
  )
  |> string.append("-")
  |> string.append(date.day |> int.to_string |> string.pad_start(2, "0"))
}
