import gleam/list
import gleam/option.{None, Some}
import tasks/domain/due
import tasks/domain/model.{type Todo, Done}
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/task_id.{type TaskId}

pub type Classification {
  Classification(
    eligible: List(scheduling_model.SchedulingTask),
    excluded: List(scheduling_model.ExcludedTask),
    identities: List(#(Int, TaskId)),
  )
}

/// Classify in stable UUIDv7 order and assign dense integer IDs only for the
/// search. String UUID comparisons in the optimizer's hot loops are measurably
/// more expensive, while these temporary IDs never cross the scheduler boundary.
pub fn classify(
  tasks: List(Todo),
  planning_start_seconds: Int,
) -> Classification {
  let ordered = list.sort(tasks, by: fn(a, b) { task_id.compare(a.id, b.id) })
  let #(_, eligible, excluded, identities) =
    list.fold(ordered, #(0, [], [], []), fn(acc, task) {
      let #(next_index, eligible, excluded, identities) = acc
      case scheduling_task(task, next_index, planning_start_seconds) {
        Ok(projected) -> #(next_index + 1, [projected, ..eligible], excluded, [
          #(next_index, task.id),
          ..identities
        ])
        Error(reason) -> #(
          next_index,
          eligible,
          [scheduling_model.ExcludedTask(task.id, reason), ..excluded],
          identities,
        )
      }
    })
  Classification(
    list.reverse(eligible),
    list.reverse(excluded),
    list.reverse(identities),
  )
}

fn scheduling_task(
  task: Todo,
  index: Int,
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
            index,
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
