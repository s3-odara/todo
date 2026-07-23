import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import scheduling_fixture
import simplifile
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/timeline.{type AbsoluteInterval}

const minute_seconds = 60

pub type OracleScenario {
  OracleScenario(
    name: String,
    tasks: List(scheduling_model.SchedulingTask),
    projected: List(AbsoluteInterval),
    witness: List(scheduling_model.ScheduleBlock),
  )
}

type OracleResult {
  OracleResult(name: String, witness: List(scheduling_model.ScheduleBlock))
}

pub fn load(cases_path: String, results_path: String) {
  use corpus <- result.try(scheduling_fixture.load(cases_path))
  let scheduling_fixture.FixtureCorpus(cases, _) = corpus
  use results_text <- result.try(
    simplifile.read(results_path)
    |> result.map_error(fn(error) {
      results_path <> ": read failed: " <> simplifile.describe_error(error)
    }),
  )
  use oracle_results <- result.try(
    json.parse(from: results_text, using: results_decoder())
    |> result.map_error(fn(_) { "invalid medium oracle results JSON" }),
  )
  cases
  |> list.try_map(fn(case_scenario) {
    let scheduling_fixture.FixtureScenario(name, tasks, projected) =
      case_scenario
    use oracle <- result.try(
      list.find(oracle_results, fn(candidate) {
        let OracleResult(candidate_name, _) = candidate
        candidate_name == name
      })
      |> result.map_error(fn(_) { "missing medium oracle result: " <> name }),
    )
    let OracleResult(_, witness) = oracle
    Ok(OracleScenario(name, tasks, projected, witness))
  })
}

fn results_decoder() {
  use results <- decode.field(
    "results",
    decode.list(of: oracle_result_decoder()),
  )
  decode.success(results)
}

fn oracle_result_decoder() {
  use name <- decode.field("name", decode.string)
  use blocks <- decode.field("blocks", decode.list(of: block_decoder()))
  decode.success(OracleResult(name, blocks))
}

fn block_decoder() {
  use task_id <- decode.field("task_id", decode.int)
  use start <- decode.field("start_minute", decode.int)
  use end <- decode.field("end_minute", decode.int)
  decode.success(scheduling_model.ScheduleBlock(
    task_id,
    start * minute_seconds,
    end * minute_seconds,
  ))
}
