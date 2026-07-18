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

const benchmark_header = "scenario|weighted_estimate|estimate_p1|estimate_p2|estimate_p3|estimate_p4|estimate_p5|initial_unscheduled|initial_policy_error|final_unscheduled|final_policy_error|final_unscheduled_p1|final_unscheduled_p2|final_unscheduled_p3|final_unscheduled_p4|final_unscheduled_p5|oracle_unscheduled|oracle_policy_error|primary_regret|policy_regret|blocks|accepted_moves|greedy_us|hill_climb_us|valid"

const baseline_header = "scenario|weighted_estimate|estimate_p1|estimate_p2|estimate_p3|estimate_p4|estimate_p5|final_unscheduled|final_policy_error|final_unscheduled_p1|final_unscheduled_p2|final_unscheduled_p3|final_unscheduled_p4|final_unscheduled_p5|valid"

type PriorityMinutes {
  PriorityMinutes(p1: Int, p2: Int, p3: Int, p4: Int, p5: Int)
}

type Row {
  Row(
    scenario: String,
    weighted_estimate: Int,
    priority_estimates: PriorityMinutes,
    final_unscheduled: Int,
    final_policy_error: Float,
    priority_unscheduled: PriorityMinutes,
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
  Change(
    primary_delta: Int,
    policy_delta: Float,
    weighted_estimate: Int,
    priority_estimates: PriorityMinutes,
    priority_deltas: PriorityMinutes,
    scenario: String,
  )
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
    weighted_estimate,
    estimate_p1,
    estimate_p2,
    estimate_p3,
    estimate_p4,
    estimate_p5,
    _,
    _,
    final_unscheduled,
    final_policy_error,
    final_unscheduled_p1,
    final_unscheduled_p2,
    final_unscheduled_p3,
    final_unscheduled_p4,
    final_unscheduled_p5,
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
    parse_int(weighted_estimate),
    parse_priority_minutes(
      estimate_p1,
      estimate_p2,
      estimate_p3,
      estimate_p4,
      estimate_p5,
    ),
    parse_int(final_unscheduled),
    parse_float(final_policy_error),
    parse_priority_minutes(
      final_unscheduled_p1,
      final_unscheduled_p2,
      final_unscheduled_p3,
      final_unscheduled_p4,
      final_unscheduled_p5,
    ),
    parse_valid(valid),
    parse_optional_int(primary_regret),
    parse_optional_float(policy_regret),
  )
}

fn parse_baseline_row(line: String) -> Row {
  let assert [
    scenario,
    weighted_estimate,
    estimate_p1,
    estimate_p2,
    estimate_p3,
    estimate_p4,
    estimate_p5,
    final_unscheduled,
    final_policy_error,
    final_unscheduled_p1,
    final_unscheduled_p2,
    final_unscheduled_p3,
    final_unscheduled_p4,
    final_unscheduled_p5,
    valid,
  ] = string.split(line, "|")
  Row(
    scenario,
    parse_int(weighted_estimate),
    parse_priority_minutes(
      estimate_p1,
      estimate_p2,
      estimate_p3,
      estimate_p4,
      estimate_p5,
    ),
    parse_int(final_unscheduled),
    parse_float(final_policy_error),
    parse_priority_minutes(
      final_unscheduled_p1,
      final_unscheduled_p2,
      final_unscheduled_p3,
      final_unscheduled_p4,
      final_unscheduled_p5,
    ),
    parse_valid(valid),
    None,
    None,
  )
}

fn parse_priority_minutes(p1, p2, p3, p4, p5) {
  PriorityMinutes(
    parse_int(p1),
    parse_int(p2),
    parse_int(p3),
    parse_int(p4),
    parse_int(p5),
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
  case dict.is_empty(candidate) {
    True -> panic as "candidate has no scenarios"
    False -> Nil
  }
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
      case
        old.weighted_estimate == new.weighted_estimate
        && old.priority_estimates == new.priority_estimates
        && new.weighted_estimate > 0
      {
        False ->
          panic as { "workload metadata differs in scenario " <> old.scenario }
        True -> Nil
      }
      let primary_delta = new.final_unscheduled - old.final_unscheduled
      let policy_delta = new.final_policy_error -. old.final_policy_error
      let priority_deltas =
        subtract_priority_minutes(
          new.priority_unscheduled,
          old.priority_unscheduled,
        )
      case weighted_minutes(priority_deltas) == primary_delta {
        False ->
          panic as { "priority totals differ in scenario " <> old.scenario }
        True -> Nil
      }
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
        [
          Change(
            primary_delta,
            policy_delta,
            new.weighted_estimate,
            new.priority_estimates,
            priority_deltas,
            old.scenario,
          ),
          ..changes
        ],
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
  let total_weighted_estimate =
    list.fold(stats.changes, 0, fn(total, change) {
      total + change.weighted_estimate
    })
  io.println(
    "primary loss pp aggregate:    "
    <> float.to_string(loss_percentage(
      stats.primary_delta,
      total_weighted_estimate,
    )),
  )
  print_loss_distribution(
    "primary loss pp p50/p95/worst:",
    list.map(stats.changes, fn(change) {
      loss_percentage(change.primary_delta, change.weighted_estimate)
    }),
  )
  [1, 2, 3, 4, 5]
  |> list.each(fn(priority) { print_priority_summary(stats.changes, priority) })
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

fn print_loss_distribution(label: String, values: List(Float)) {
  case values {
    [] -> io.println(label <> " -")
    _ ->
      io.println(
        label
        <> " "
        <> float.to_string(nearest_rank(values, 50))
        <> "/"
        <> float.to_string(nearest_rank(values, 95))
        <> "/"
        <> float.to_string(nearest_rank(values, 100)),
      )
  }
}

fn print_priority_summary(changes: List(Change), priority: Int) {
  let applicable =
    list.filter(changes, fn(change) {
      priority_minutes(change.priority_estimates, priority) > 0
    })
  case applicable {
    [] ->
      io.println(
        "priority " <> int.to_string(priority) <> " loss pp:              -",
      )
    _ -> {
      let #(total_delta, total_estimate) =
        list.fold(applicable, #(0, 0), fn(totals, change) {
          #(
            totals.0 + priority_minutes(change.priority_deltas, priority),
            totals.1 + priority_minutes(change.priority_estimates, priority),
          )
        })
      let losses =
        list.map(applicable, fn(change) {
          loss_percentage(
            priority_minutes(change.priority_deltas, priority),
            priority_minutes(change.priority_estimates, priority),
          )
        })
      io.println(
        "priority "
        <> int.to_string(priority)
        <> " loss pp aggregate/p50/p95/worst: "
        <> float.to_string(loss_percentage(total_delta, total_estimate))
        <> "/"
        <> float.to_string(nearest_rank(losses, 50))
        <> "/"
        <> float.to_string(nearest_rank(losses, 95))
        <> "/"
        <> float.to_string(nearest_rank(losses, 100)),
      )
    }
  }
}

// Nearest-rank keeps percentile results tied to an observed scenario.
fn nearest_rank(values: List(Float), percentile: Int) -> Float {
  let sorted = list.sort(values, by: float.compare)
  let rank = { percentile * list.length(sorted) + 99 } / 100
  let assert [value, ..] = list.drop(sorted, int.max(0, rank - 1))
  value
}

fn loss_percentage(delta: Int, estimate: Int) -> Float {
  int.to_float(delta) /. int.to_float(estimate) *. 100.0
}

fn subtract_priority_minutes(a: PriorityMinutes, b: PriorityMinutes) {
  let PriorityMinutes(a1, a2, a3, a4, a5) = a
  let PriorityMinutes(b1, b2, b3, b4, b5) = b
  PriorityMinutes(a1 - b1, a2 - b2, a3 - b3, a4 - b4, a5 - b5)
}

fn weighted_minutes(minutes: PriorityMinutes) {
  let PriorityMinutes(p1, p2, p3, p4, p5) = minutes
  p1 + p2 * 2 + p3 * 4 + p4 * 8 + p5 * 16
}

fn priority_minutes(minutes: PriorityMinutes, priority: Int) {
  let PriorityMinutes(p1, p2, p3, p4, p5) = minutes
  case priority {
    1 -> p1
    2 -> p2
    3 -> p3
    4 -> p4
    5 -> p5
    _ -> 0
  }
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
