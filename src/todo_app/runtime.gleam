import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/app_state.{type AppState, AppState}
import tasks/domain/availability
import tasks/domain/filter.{type StatusFilter, type TimeFilter}
import tasks/domain/model.{type TaskError, type Todo}
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/scheduler
import tasks/domain/task_id.{type TaskId}
import tasks/domain/tasks
import todo_app/cli.{
  type Command, type Outcome, Add, AvailabilityList, GenerateSchedule, Help,
  ListScheduled, ListTasks, MutateAvailability, RunDelete, RunDone, RunReopen,
  RunUpdate,
}

/// A pure command result. Persistence stays in the outer shell so command
/// behavior can be tested without simulating a store.
pub type Execution {
  Execution(state: AppState, outcome: Outcome, changed: Bool)
}

pub fn execute(
  command: Command,
  state: AppState,
  now: Timestamp,
  offset: Duration,
) -> Execution {
  case command {
    Help -> unchanged(state, cli.help())
    Add(id, values) -> {
      let #(updated_tasks, added) = tasks.add(state.tasks, id, values)
      changed(AppState(..state, tasks: updated_tasks), cli.added(added))
    }
    ListTasks(status, time_filter) -> {
      let items =
        state.tasks
        |> tasks.visible(status, filter.resolve(time_filter, now, offset))
        |> tasks.sorted_by_id
      unchanged(state, cli.listed(items, status, offset))
    }
    ListScheduled(status, time_filter) -> {
      let #(saved_offset, items) =
        scheduled_list(state, status, time_filter, now)
      unchanged(state, cli.scheduled_listed(saved_offset, items))
    }
    GenerateSchedule ->
      case scheduler.generate(state, scheduler.context(now, offset)) {
        Ok(generated) -> {
          let scheduling_model.GenerationResult(saved_schedule, _) = generated
          changed(
            AppState(..state, current_schedule: Some(saved_schedule)),
            cli.schedule_generated(generated),
          )
        }
        Error(error) -> unchanged(state, cli.scheduling_error(error))
      }
    RunDone(selector) ->
      mutate_selected(state, selector, tasks.complete, cli.completed)
    RunReopen(selector) ->
      mutate_selected(state, selector, tasks.reopen, cli.reopened)
    RunUpdate(selector, values) ->
      mutate_selected(
        state,
        selector,
        fn(items, id) { tasks.update(items, id, values) },
        cli.updated,
      )
    RunDelete(selector) ->
      mutate_selected(state, selector, tasks.delete, cli.deleted)
    AvailabilityList ->
      unchanged(state, cli.availability_listed(state.availability))
    MutateAvailability(mutation) -> {
      let updated =
        AppState(
          ..state,
          availability: availability.apply(state.availability, mutation),
        )
      Execution(updated, cli.availability_updated(), updated != state)
    }
  }
}

fn mutate_selected(
  state: AppState,
  selector: String,
  mutation: fn(List(Todo), TaskId) -> Result(#(List(Todo), Todo), TaskError),
  outcome: fn(Todo) -> Outcome,
) -> Execution {
  case tasks.resolve_id(state.tasks, selector) {
    Error(error) -> unchanged(state, cli.domain_error(error))
    Ok(id) ->
      case mutation(state.tasks, id) {
        Error(error) -> unchanged(state, cli.domain_error(error))
        Ok(#(updated_tasks, selected)) -> {
          let updated = AppState(..state, tasks: updated_tasks)
          // Updating a field to its existing value should not cause a needless write.
          Execution(updated, outcome(selected), updated != state)
        }
      }
  }
}

fn scheduled_list(
  state: AppState,
  status: StatusFilter,
  time_filter: TimeFilter,
  now: Timestamp,
) {
  case state.current_schedule {
    None -> #(0, [])
    Some(saved) -> {
      let offset = duration.seconds(saved.utc_offset_seconds)
      // Saved blocks keep the offset used when they were generated.
      let window = filter.resolve(time_filter, now, offset)
      let items =
        saved.blocks
        |> list.filter_map(fn(block) {
          use task <- result.try(
            list.find(state.tasks, fn(task) { task.id == block.task_id }),
          )
          case
            filter.status_matches(status, task.status)
            && filter.block_overlaps(
              block.start_seconds,
              block.end_seconds,
              window,
            )
          {
            True -> Ok(#(block, task))
            False -> Error(Nil)
          }
        })
        |> list.sort(by: fn(a, b) { saved_block_compare(a.0, b.0) })
      #(saved.utc_offset_seconds, items)
    }
  }
}

fn saved_block_compare(
  a: scheduling_model.SavedScheduleBlock,
  b: scheduling_model.SavedScheduleBlock,
) {
  case int.compare(a.start_seconds, b.start_seconds) {
    order.Eq ->
      case task_id.compare(a.task_id, b.task_id) {
        order.Eq -> int.compare(a.end_seconds, b.end_seconds)
        other -> other
      }
    other -> other
  }
}

fn unchanged(state: AppState, outcome: Outcome) -> Execution {
  Execution(state, outcome, False)
}

fn changed(state: AppState, outcome: Outcome) -> Execution {
  Execution(state, outcome, True)
}
