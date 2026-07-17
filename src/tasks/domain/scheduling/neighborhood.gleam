import gleam/int
import gleam/list
import tasks/domain/scheduling/model.{type SchedulingTask}

pub opaque type Rebuild {
  Rebuild(tasks: List(SchedulingTask))
}

type Generated {
  Generated(reversed: List(Rebuild), remaining: Int)
}

pub fn tasks(rebuild: Rebuild) -> List(SchedulingTask) {
  rebuild.tasks
}

/// Generate ID-ordered single, pair, and triple rebuilds within one budget.
pub fn generate(tasks: List(SchedulingTask), limit: Int) -> List(Rebuild) {
  let ordered = list.sort(tasks, by: fn(a, b) { int.compare(a.id, b.id) })
  let initial = Generated([], int.max(0, limit))
  let singles = combinations(ordered, 1, [], initial)
  let pairs = combinations(ordered, 2, [], singles)
  let Generated(reversed, _) = combinations(ordered, 3, [], pairs)
  list.reverse(reversed)
}

// Walk combinations lazily. Exhausting the shared budget stops input traversal.
fn combinations(items, size, selected, generated) {
  let Generated(_, remaining) = generated
  case remaining <= 0, size, items {
    True, _, _ -> generated
    False, 0, _ -> add_permutations(list.reverse(selected), generated)
    False, _, [] -> generated
    False, _, [item, ..rest] -> {
      let with_item =
        combinations(rest, size - 1, [item, ..selected], generated)
      combinations(rest, size, selected, with_item)
    }
  }
}

fn add_permutations(selected, generated) {
  let values = case selected {
    [a] -> [[a]]
    [a, b] -> [[a, b], [b, a]]
    [a, b, c] -> [
      [a, b, c],
      [a, c, b],
      [b, a, c],
      [b, c, a],
      [c, a, b],
      [c, b, a],
    ]
    _ -> []
  }
  add(values, generated)
}

fn add(values, generated) {
  let Generated(reversed, remaining) = generated
  case values, remaining <= 0 {
    _, True | [], _ -> generated
    [value, ..rest], False ->
      add(rest, Generated([Rebuild(value), ..reversed], remaining - 1))
  }
}
