import gleam/list
import gleeunit/should
import scheduling_oracle_fixture
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/timeline.{SearchSpace}

const cases_path = "benchmark/oracles/medium-cases-v1.json"

const results_path = "benchmark/oracles/medium-results-v1.json"

pub fn medium_oracle_witnesses_are_valid_test() {
  let assert Ok(scenarios) =
    scheduling_oracle_fixture.load(cases_path, results_path)
  list.length(scenarios) |> should.equal(8)
  scenarios
  |> list.each(fn(scenario) {
    let scheduling_oracle_fixture.OracleScenario(_, tasks, projected, witness) =
      scenario
    invariant.validate_generation(witness, tasks, SearchSpace(projected, 0, 0))
    |> should.equal(Ok(Nil))
  })
}
