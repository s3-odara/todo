import argv
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import simplifile

const epsilon = 0.000000000001

const benchmark_header = "scenario|initial_unscheduled|initial_policy_error|final_unscheduled|final_policy_error|oracle_unscheduled|oracle_policy_error|primary_regret|policy_regret|blocks|accepted_moves|greedy_us|hill_climb_us|valid"

const baseline_header = "scenario|final_unscheduled|final_policy_error|valid"

type Row {
  Row(
    scenario: String,
    final_unscheduled: Int,
    final_policy_error: Float,
    valid: Bool,
    primary_regret: Option(Int),
    policy_regret: Option(Float),
  )
}

type Stats {
  Stats(
    primary_wins: Int,
    primary_ties: Int,
    primary_losses: Int,
    primary_delta: Int,
    secondary_wins: Int,
    secondary_ties: Int,
    secondary_losses: Int,
    changes: List(Change),
  )
}

type Change {
  Change(primary_delta: Int, policy_delta: Float, scenario: String)
}

pub fn main() {
  case argv.load().arguments {
    [path] -> summarize_oracle(load(path))
    [baseline, candidate] -> compare(load(baseline), load(candidate))
    _ ->
      panic as "usage: scheduling_quality_compare RESULT\n   or: scheduling_quality_compare BASELINE CANDIDATE"
  }
}

fn load(path: String) -> Dict(String, Row) {
  let text = case simplifile.read(path) {
    Ok(text) -> text
    Error(error) ->
      panic as { path <> ": read failed: " <> simplifile.describe_error(error) }
  }
  let assert [header, ..lines] = text |> string.trim |> string.split("\n")
  let parse = case header {
    value if value == benchmark_header -> parse_benchmark_row
    value if value == baseline_header -> parse_baseline_row
    _ -> panic as { path <> ": unsupported benchmark schema" }
  }
  lines
  |> list.filter(fn(line) { string.trim(line) != "" })
  |> list.fold(dict.new(), fn(rows, line) {
    let row = parse(line)
    case dict.has_key(rows, row.scenario) {
      True -> panic as { path <> ": duplicate scenario " <> row.scenario }
      False -> dict.insert(rows, row.scenario, row)
    }
  })
}

fn parse_benchmark_row(line: String) -> Row {
  let assert [
    scenario,
    _,
    _,
    final_unscheduled,
    final_policy_error,
    _,
    _,
    primary_regret,
    policy_regret,
    _,
    _,
    _,
    _,
    valid,
  ] = string.split(line, "|")
  Row(
    scenario,
    parse_int(final_unscheduled),
    parse_float(final_policy_error),
    parse_valid(valid),
    parse_optional_int(primary_regret),
    parse_optional_float(policy_regret),
  )
}

fn parse_baseline_row(line: String) -> Row {
  let assert [scenario, final_unscheduled, final_policy_error, valid] =
    string.split(line, "|")
  Row(
    scenario,
    parse_int(final_unscheduled),
    parse_float(final_policy_error),
    parse_valid(valid),
    None,
    None,
  )
}

fn parse_int(value: String) -> Int {
  let assert Ok(value) = int.parse(value)
  value
}

fn parse_float(value: String) -> Float {
  let assert Ok(value) = float.parse(value)
  value
}

fn parse_valid(value: String) -> Bool {
  case value {
    "true" -> True
    "false" -> False
    _ -> panic as "invalid benchmark validity"
  }
}

fn parse_optional_int(value: String) -> Option(Int) {
  case value {
    "-" -> None
    _ -> Some(parse_int(value))
  }
}

fn parse_optional_float(value: String) -> Option(Float) {
  case value {
    "-" -> None
    _ -> Some(parse_float(value))
  }
}

fn compare(baseline: Dict(String, Row), candidate: Dict(String, Row)) {
  // A full baseline intentionally serves quick runs, so unused baseline rows
  // are allowed while every candidate row must still have a reference.
  let stats =
    candidate
    |> dict.to_list
    |> list.fold(empty_stats(), fn(stats, entry) {
      let #(scenario, new) = entry
      let old = case dict.get(baseline, scenario) {
        Ok(row) -> row
        Error(_) ->
          panic as {
            "candidate scenario is missing from baseline: " <> scenario
          }
      }
      compare_row(stats, old, new)
    })
  print_comparison(dict.size(candidate), stats)
}

fn compare_row(stats: Stats, old: Row, new: Row) -> Stats {
  case old.valid && new.valid {
    False -> panic as { "invalid schedule in scenario " <> old.scenario }
    True -> {
      let primary_delta = new.final_unscheduled - old.final_unscheduled
      let policy_delta = new.final_policy_error -. old.final_policy_error
      let Stats(
        primary_wins,
        primary_ties,
        primary_losses,
        total_delta,
        secondary_wins,
        secondary_ties,
        secondary_losses,
        changes,
      ) = stats
      let #(next_primary_wins, next_primary_ties, next_primary_losses) = case
        int.compare(primary_delta, 0)
      {
        order.Lt -> #(primary_wins + 1, primary_ties, primary_losses)
        order.Gt -> #(primary_wins, primary_ties, primary_losses + 1)
        order.Eq -> #(primary_wins, primary_ties + 1, primary_losses)
      }
      let #(next_secondary_wins, next_secondary_ties, next_secondary_losses) = case
        primary_delta
      {
        0 if policy_delta <. { 0.0 -. epsilon } -> #(
          secondary_wins + 1,
          secondary_ties,
          secondary_losses,
        )
        0 if policy_delta >. epsilon -> #(
          secondary_wins,
          secondary_ties,
          secondary_losses + 1,
        )
        0 -> #(secondary_wins, secondary_ties + 1, secondary_losses)
        _ -> #(secondary_wins, secondary_ties, secondary_losses)
      }
      Stats(
        next_primary_wins,
        next_primary_ties,
        next_primary_losses,
        total_delta + primary_delta,
        next_secondary_wins,
        next_secondary_ties,
        next_secondary_losses,
        [Change(primary_delta, policy_delta, old.scenario), ..changes],
      )
    }
  }
}

fn summarize_oracle(rows: Dict(String, Row)) {
  let exact =
    rows
    |> dict.to_list
    |> list.map(fn(entry) { entry.1 })
    |> list.filter(fn(row) { row.primary_regret != None })
  case exact {
    [] -> panic as "no oracle rows"
    _ -> {
      let #(primary_optimal, lexicographic_optimal, total, worst, policy_total) =
        list.fold(exact, #(0, 0, 0, 0, 0.0), fn(summary, row) {
          let #(
            primary_optimal,
            lexicographic_optimal,
            total,
            worst,
            policy_total,
          ) = summary
          let primary = option_int(row.primary_regret)
          let policy = option_float(row.policy_regret)
          #(
            primary_optimal + bool_int(primary == 0),
            lexicographic_optimal
              + bool_int(
              primary == 0 && float.absolute_value(policy) <=. epsilon,
            ),
            total + primary,
            int.max(worst, primary),
            policy_total
              +. case primary == 0 {
              True -> policy
              False -> 0.0
            },
          )
        })
      let count = list.length(exact)
      io.println("oracle cases:                 " <> int.to_string(count))
      io.println(
        "primary optimal:              " <> fraction(primary_optimal, count),
      )
      io.println(
        "lexicographic optimal:        "
        <> fraction(lexicographic_optimal, count),
      )
      io.println("primary regret total:         " <> int.to_string(total))
      io.println("primary regret worst:         " <> int.to_string(worst))
      io.println(
        "conditional policy regret:    " <> float.to_string(policy_total),
      )
      io.println("worst cases:")
      exact
      |> list.sort(by: oracle_worst_first)
      |> list.take(5)
      |> list.each(fn(row) {
        io.println(
          "  "
          <> row.scenario
          <> ": primary="
          <> optional_int_string(row.primary_regret)
          <> ", policy="
          <> optional_float_string(row.policy_regret),
        )
      })
    }
  }
}

fn print_comparison(count: Int, stats: Stats) {
  io.println("matched cases:                " <> int.to_string(count))
  io.println(
    "primary W/T/L:                "
    <> triple(stats.primary_wins, stats.primary_ties, stats.primary_losses),
  )
  io.println(
    "primary total delta:          " <> signed_int(stats.primary_delta),
  )
  io.println(
    "secondary W/T/L on ties:      "
    <> triple(
      stats.secondary_wins,
      stats.secondary_ties,
      stats.secondary_losses,
    ),
  )
  io.println("largest primary regressions:")
  stats.changes
  |> list.filter(fn(change) { change.primary_delta > 0 })
  |> list.sort(by: fn(a, b) { int.compare(b.primary_delta, a.primary_delta) })
  |> list.take(5)
  |> list.each(print_change)
  io.println("largest primary improvements:")
  stats.changes
  |> list.filter(fn(change) { change.primary_delta < 0 })
  |> list.sort(by: fn(a, b) { int.compare(a.primary_delta, b.primary_delta) })
  |> list.take(5)
  |> list.each(print_change)
}

fn print_change(change: Change) {
  io.println(
    "  "
    <> change.scenario
    <> ": primary="
    <> signed_int(change.primary_delta)
    <> ", policy="
    <> signed_float(change.policy_delta),
  )
}

fn oracle_worst_first(a: Row, b: Row) {
  case int.compare(option_int(b.primary_regret), option_int(a.primary_regret)) {
    order.Eq ->
      float.compare(
        option_float(b.policy_regret),
        option_float(a.policy_regret),
      )
    other -> other
  }
}

fn empty_stats() {
  Stats(0, 0, 0, 0, 0, 0, 0, [])
}

fn option_int(value: Option(Int)) {
  case value {
    Some(value) -> value
    None -> 0
  }
}

fn option_float(value: Option(Float)) {
  case value {
    Some(value) -> value
    None -> 0.0
  }
}

fn optional_int_string(value: Option(Int)) {
  case value {
    Some(value) -> int.to_string(value)
    None -> "-"
  }
}

fn optional_float_string(value: Option(Float)) {
  case value {
    Some(value) -> float.to_string(value)
    None -> "-"
  }
}

fn bool_int(value: Bool) {
  case value {
    True -> 1
    False -> 0
  }
}

fn fraction(value: Int, total: Int) {
  int.to_string(value) <> "/" <> int.to_string(total)
}

fn triple(first: Int, second: Int, third: Int) {
  int.to_string(first)
  <> "/"
  <> int.to_string(second)
  <> "/"
  <> int.to_string(third)
}

fn signed_int(value: Int) {
  case value > 0 {
    True -> "+" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn signed_float(value: Float) {
  case value >. 0.0 {
    True -> "+" <> float.to_string(value)
    False -> float.to_string(value)
  }
}
