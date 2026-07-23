#!/usr/bin/env python3
"""Generate cached exact medium scheduling oracles with OR-Tools CP-SAT."""

from __future__ import annotations

import json
import math
from fractions import Fraction
from pathlib import Path

from ortools.sat.python import cp_model
import ortools

ROOT = Path(__file__).resolve().parents[2]
CASES_PATH = ROOT / "benchmark/oracles/medium-cases-v1.json"
RESULTS_PATH = ROOT / "benchmark/oracles/medium-results-v1.json"
INT64_MAX = (1 << 63) - 1
PRIORITY_WEIGHTS = {1: 1, 2: 2, 3: 4, 4: 8, 5: 16}
POLICIES = {"asap", "spread", "near_deadline"}


def polynomial_square(values: list[Fraction]) -> list[Fraction]:
    result = [Fraction(0) for _ in range(len(values) * 2 - 1)]
    for left_index, left in enumerate(values):
        for right_index, right in enumerate(values):
            result[left_index + right_index] += left * right
    return result


def transition_policy_error(
    policy: str,
    minute: int,
    deadline: int,
    estimate: int,
    completed: int,
    active: int,
) -> Fraction:
    """Exact integral over one minute in normalized deadline coordinates."""
    d = Fraction(deadline)
    t = Fraction(minute)
    if policy == "spread":
        desired = [t / d, Fraction(1, deadline), Fraction(0)]
    elif policy == "near_deadline":
        desired = [t * t / (d * d), 2 * t / (d * d), Fraction(1, deadline * deadline)]
    elif policy == "asap":
        desired = [
            2 * t / d - t * t / (d * d),
            Fraction(2, deadline) - 2 * t / (d * d),
            Fraction(-1, deadline * deadline),
        ]
    else:
        raise ValueError(f"unsupported policy: {policy}")

    actual = [Fraction(completed, estimate), Fraction(active, estimate), Fraction(0)]
    difference = [actual[index] - desired[index] for index in range(3)]
    squared = polynomial_square(difference)
    return sum(
        coefficient / (power + 1)
        for power, coefficient in enumerate(squared)
    ) / deadline


def case_horizon(case: dict) -> int:
    return max(
        [task["deadline_minute"] for task in case["tasks"]]
        + [interval["end_minute"] for interval in case["availability"]]
    )


def availability_mask(case: dict) -> list[bool]:
    horizon = case_horizon(case)
    return [
        any(
            interval["start_minute"] <= minute < interval["end_minute"]
            for interval in case["availability"]
        )
        for minute in range(horizon)
    ]


def minimum_split_automaton(minimum: int):
    if minimum == 1:
        return 0, [0, 1], [
            (0, 0, 0),
            (0, 1, 1),
            (1, 0, 0),
            (1, 1, 1),
        ]
    transitions = [(0, 0, 0), (0, 1, 1), (minimum, 0, 0), (minimum, 1, minimum)]
    for length in range(1, minimum):
        transitions.append((length, 1, length + 1))
    return 0, [0, minimum], transitions


def collect_transition_rows(
    case: dict,
) -> tuple[list[list[list[tuple[int, int, Fraction]]]], int]:
    all_rows: list[list[list[tuple[int, int, Fraction]]]] = []
    scale = 1
    for task in case["tasks"]:
        task_rows: list[list[tuple[int, int, Fraction]]] = []
        weight = PRIORITY_WEIGHTS[task["priority"]]
        for minute in range(task["deadline_minute"]):
            rows: list[tuple[int, int, Fraction]] = []
            for completed in range(task["estimate_minutes"] + 1):
                for active in (0, 1):
                    if completed + active <= task["estimate_minutes"]:
                        cost = weight * transition_policy_error(
                            task["policy"],
                            minute,
                            task["deadline_minute"],
                            task["estimate_minutes"],
                            completed,
                            active,
                        )
                        rows.append((completed, active, cost))
                        scale = math.lcm(scale, cost.denominator)
            task_rows.append(rows)
        all_rows.append(task_rows)
    return all_rows, scale


def solve_case(case: dict) -> dict:
    horizon = case_horizon(case)
    available = availability_mask(case)
    model = cp_model.CpModel()
    assignments: list[list[cp_model.IntVar]] = []
    completed_variables: list[list[cp_model.IntVar]] = []

    for task_index, task in enumerate(case["tasks"]):
        estimate = task["estimate_minutes"]
        deadline = task["deadline_minute"]
        minimum = min(estimate, task["minimum_split_minutes"])
        task_assignments = [
            model.new_bool_var(f"x_{task_index}_{minute}")
            for minute in range(horizon)
        ]
        for minute, variable in enumerate(task_assignments):
            if minute >= deadline or not available[minute]:
                model.add(variable == 0)
        model.add(sum(task_assignments) <= estimate)
        start, finals, transitions = minimum_split_automaton(minimum)
        model.add_automaton(task_assignments, start, finals, transitions)

        completed = [
            model.new_int_var(0, estimate, f"completed_{task_index}_{minute}")
            for minute in range(deadline + 1)
        ]
        model.add(completed[0] == 0)
        for minute in range(deadline):
            model.add(completed[minute + 1] == completed[minute] + task_assignments[minute])
        assignments.append(task_assignments)
        completed_variables.append(completed)

    for minute in range(horizon):
        model.add(sum(task[minute] for task in assignments) <= 1)

    primary = model.new_int_var(0, sum(
        PRIORITY_WEIGHTS[task["priority"]] * task["estimate_minutes"]
        for task in case["tasks"]
    ), "weighted_unscheduled")
    model.add(primary == sum(
        PRIORITY_WEIGHTS[task["priority"]]
        * (task["estimate_minutes"] - sum(assignments[index]))
        for index, task in enumerate(case["tasks"])
    ))

    fractional_rows, scale = collect_transition_rows(case)
    if scale > INT64_MAX:
        raise RuntimeError(f"{case['name']}: policy scale exceeds int64: {scale}")

    policy_terms = []
    policy_upper_bound = 0
    for task_index, task in enumerate(case["tasks"]):
        for minute in range(task["deadline_minute"]):
            rows = [
                (completed, active, cost.numerator * (scale // cost.denominator))
                for completed, active, cost in fractional_rows[task_index][minute]
            ]
            integer_costs = [cost for _, _, cost in rows]
            lower = min(integer_costs)
            upper = max(integer_costs)
            cost_variable = model.new_int_var(lower, upper, f"policy_{task_index}_{minute}")
            model.add_allowed_assignments(
                [completed_variables[task_index][minute], assignments[task_index][minute], cost_variable],
                rows,
            )
            policy_terms.append(cost_variable)
            policy_upper_bound += upper
    if policy_upper_bound > INT64_MAX:
        raise RuntimeError(
            f"{case['name']}: policy objective bound exceeds int64: {policy_upper_bound}"
        )
    policy_total = model.new_int_var(0, policy_upper_bound, "weighted_policy_error")
    model.add(policy_total == sum(policy_terms))

    solver = cp_model.CpSolver()
    solver.parameters.num_search_workers = 1
    solver.parameters.random_seed = 0

    model.minimize(primary)
    status = solver.solve(model)
    if status != cp_model.OPTIMAL:
        raise RuntimeError(f"{case['name']}: primary solve was {solver.status_name(status)}")
    primary_optimum = solver.value(primary)

    model.add(primary == primary_optimum)
    model.minimize(policy_total)
    status = solver.solve(model)
    if status != cp_model.OPTIMAL:
        raise RuntimeError(f"{case['name']}: policy solve was {solver.status_name(status)}")

    policy_integer = solver.value(policy_total)
    policy_fraction = Fraction(policy_integer, scale)
    blocks = []
    for task_index, task in enumerate(case["tasks"]):
        start = None
        for minute in range(horizon + 1):
            active = minute < horizon and solver.value(assignments[task_index][minute]) == 1
            if active and start is None:
                start = minute
            elif not active and start is not None:
                blocks.append({
                    "task_id": task["id"],
                    "start_minute": start,
                    "end_minute": minute,
                })
                start = None
    blocks.sort(key=lambda block: (block["start_minute"], block["task_id"], block["end_minute"]))

    print(
        f"{case['name']}: primary={primary_optimum}, "
        f"policy={float(policy_fraction):.12g}, blocks={len(blocks)}"
    )
    return {
        "name": case["name"],
        "blocks": blocks,
    }


def main() -> None:
    document = json.loads(CASES_PATH.read_bytes())
    results = [solve_case(case) for case in document["scenarios"]]
    output = {
        "ortools_version": ortools.__version__,
        "results": results,
    }
    temporary = RESULTS_PATH.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(output, indent=2) + "\n")
    temporary.replace(RESULTS_PATH)


if __name__ == "__main__":
    main()
