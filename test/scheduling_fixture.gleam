import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import scheduling_benchmark_hash
import simplifile
import tasks/domain/policy as scheduling_policy
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/timeline.{type AbsoluteInterval, AbsoluteInterval}

const minute_seconds = 60

const permutation_seeds = [101, 211, 307]

pub type FixtureScenario {
  FixtureScenario(
    name: String,
    tasks: List(scheduling_model.SchedulingTask),
    projected: List(AbsoluteInterval),
  )
}

pub type FixtureCorpus {
  FixtureCorpus(
    base: List(FixtureScenario),
    id_permutations: List(FixtureScenario),
  )
}

pub fn load(path: String) -> Result(FixtureCorpus, String) {
  use text <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(error) {
      path <> ": read failed: " <> simplifile.describe_error(error)
    }),
  )
  decode_fixture(text)
}

/// This decoder intentionally trusts the fixed, generated fixture values and
/// validates only their JSON shape and scheduling-policy spelling.
fn decode_fixture(text: String) -> Result(FixtureCorpus, String) {
  json.parse(from: text, using: corpus_decoder())
  |> result.map(fn(base) {
    FixtureCorpus(base, list.flat_map(base, id_permutations))
  })
  |> result.map_error(fn(_) { "invalid representative fixture JSON" })
}

fn corpus_decoder() {
  use scenarios <- decode.field(
    "scenarios",
    decode.list(of: scenario_decoder()),
  )
  decode.success(scenarios)
}

fn scenario_decoder() {
  use name <- decode.field("name", decode.string)
  use projected <- decode.field(
    "availability",
    decode.list(of: interval_decoder()),
  )
  use tasks <- decode.field("tasks", decode.list(of: task_decoder()))
  decode.success(FixtureScenario(name, tasks, projected))
}

fn interval_decoder() {
  use start <- decode.field("start_minute", decode.int)
  use end <- decode.field("end_minute", decode.int)
  decode.success(AbsoluteInterval(start * minute_seconds, end * minute_seconds))
}

fn task_decoder() {
  use id <- decode.field("id", decode.int)
  use estimate <- decode.field("estimate_minutes", decode.int)
  use priority <- decode.field("priority", decode.int)
  use deadline <- decode.field("deadline_minute", decode.int)
  use policy <- decode.field("policy", policy_decoder())
  use minimum_split <- decode.field("minimum_split_minutes", decode.int)
  decode.success(scheduling_model.SchedulingTask(
    id,
    estimate,
    priority,
    deadline * minute_seconds,
    policy,
    minimum_split,
  ))
}

fn policy_decoder() {
  decode.string
  |> decode.then(fn(value) {
    case scheduling_policy.parse(value) {
      Ok(policy) -> decode.success(policy)
      Error(_) ->
        decode.failure(scheduling_policy.Spread, expected: "scheduling policy")
    }
  })
}

fn id_permutations(scenario: FixtureScenario) -> List(FixtureScenario) {
  let FixtureScenario(name, tasks, projected) = scenario
  let lowbias =
    list.map(permutation_seeds, fn(seed) {
      FixtureScenario(
        name <> "__id_lowbias_" <> int.to_string(seed),
        assign_ids(tasks, lowbias_order(tasks, seed)),
        projected,
      )
    })
  list.append(lowbias, [
    FixtureScenario(
      name <> "__id_adversarial",
      assign_ids(tasks, adversarial_order(tasks)),
      projected,
    ),
  ])
}

fn lowbias_order(tasks: List(scheduling_model.SchedulingTask), seed: Int) {
  tasks
  |> list.index_map(fn(_, index) {
    #(index, scheduling_benchmark_hash.value(seed, index))
  })
  |> list.sort(by: fn(a, b) {
    case int.compare(a.1, b.1) {
      order.Eq -> int.compare(a.0, b.0)
      other -> other
    }
  })
  |> list.map(fn(entry) { entry.0 })
}

fn adversarial_order(tasks: List(scheduling_model.SchedulingTask)) {
  tasks
  |> list.index_map(fn(task, index) { #(index, task) })
  |> list.sort(by: least_urgent_first)
  |> list.map(fn(entry) { entry.0 })
}

fn least_urgent_first(
  a: #(Int, scheduling_model.SchedulingTask),
  b: #(Int, scheduling_model.SchedulingTask),
) {
  case int.compare(a.1.priority, b.1.priority) {
    order.Eq ->
      case int.compare(b.1.deadline_seconds, a.1.deadline_seconds) {
        order.Eq ->
          case int.compare(a.1.estimate_minutes, b.1.estimate_minutes) {
            order.Eq -> int.compare(a.0, b.0)
            other -> other
          }
        other -> other
      }
    other -> other
  }
}

fn assign_ids(
  tasks: List(scheduling_model.SchedulingTask),
  ordered_indices: List(Int),
) {
  let sorted_ids =
    tasks
    |> list.map(fn(task) { task.id })
    |> list.sort(by: int.compare)
  let ids_by_task =
    list.zip(ordered_indices, sorted_ids)
    |> list.sort(by: fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(entry) { entry.1 })
  list.zip(tasks, ids_by_task)
  |> list.map(fn(entry) {
    scheduling_model.SchedulingTask(..entry.0, id: entry.1)
  })
}
