import gleam/int
import gleam/list
import gleam/option.{None, Some}
import tasks/domain/due
import tasks/domain/model.{type Todo, Done}
import tasks/domain/scheduling/model as scheduling_model

pub type Classification {
  Classification(
    eligible: List(scheduling_model.SchedulingTask),
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
      case scheduling_task(task, planning_start_seconds) {
        Ok(eligible) -> #([eligible, ..acc.0], acc.1)
        Error(reason) -> #(acc.0, [
          scheduling_model.ExcludedTask(task.id, reason),
          ..acc.1
        ])
      }
    })
  Classification(list.reverse(eligible), list.reverse(excluded))
}

fn scheduling_task(
  task: Todo,
  planning_start_seconds: Int,
) -> Result(scheduling_model.SchedulingTask, scheduling_model.ExcludedReason) {
  case task.status, task.estimate_minutes, task.due {
    Done, _, _ -> Error(scheduling_model.Completed)
    _, 0, _ -> Error(scheduling_model.MissingEstimate)
    _, _, None -> Error(scheduling_model.MissingDue)
    _, _, Some(deadline) -> {
      let deadline_seconds = due.to_unix_seconds(deadline)
      case deadline_seconds <= planning_start_seconds {
        True -> Error(scheduling_model.DeadlineNotAfterStart)
        False ->
          Ok(scheduling_model.SchedulingTask(
            task.id,
            task.estimate_minutes,
            task.priority,
            deadline_seconds,
            task.scheduling_policy,
            task.minimum_split_minutes,
          ))
      }
    }
  }
}
