import gleam/int
import gleam/list
import gleam/option.{None, Some}
import tasks/domain/due
import tasks/domain/model.{type Todo, Done}
import tasks/domain/scheduling/model as scheduling_model

pub type Classification {
  Classification(
    eligible: List(Todo),
    excluded: List(scheduling_model.ExcludedTask),
  )
}

/// Classify in the specified reason precedence, returning stable task-id order.
pub fn classify(
  tasks: List(Todo),
  planning_start_seconds: Int,
) -> Classification {
  let ordered = list.sort(tasks, by: fn(a, b) { int.compare(a.id, b.id) })
  let #(eligible, excluded) =
    list.fold(ordered, #([], []), fn(acc, task) {
      case exclusion(task, planning_start_seconds) {
        None -> #([task, ..acc.0], acc.1)
        Some(reason) -> #(acc.0, [
          scheduling_model.ExcludedTask(task.id, reason),
          ..acc.1
        ])
      }
    })
  Classification(list.reverse(eligible), list.reverse(excluded))
}

pub fn exclusion(
  task: Todo,
  planning_start_seconds: Int,
) -> option.Option(scheduling_model.ExcludedReason) {
  case task.status, task.estimate_minutes, task.due {
    Done, _, _ -> Some(scheduling_model.Completed)
    _, 0, _ -> Some(scheduling_model.MissingEstimate)
    _, _, None -> Some(scheduling_model.MissingDue)
    _, _, Some(deadline) ->
      case due.to_unix_seconds(deadline) <= planning_start_seconds {
        True -> Some(scheduling_model.DeadlineNotAfterStart)
        False -> None
      }
  }
}
