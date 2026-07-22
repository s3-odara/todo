import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/app_state.{type AppState, AppState}
import tasks/domain/availability
import tasks/domain/filter.{
  type ResolvedScheduledFilter, type StatusFilter, ScheduledList, TaskList,
}
import tasks/domain/scheduling/invariant
import tasks/domain/scheduling/model as scheduling_model
import tasks/domain/scheduling/scheduler
import tasks/domain/tasks
import todo_app/cli.{
  type Command, type Outcome, Add, AvailabilityList, GenerateSchedule, Help,
  List, MutateAvailability, RunDone,
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
    Add(values) -> {
      let #(updated_tasks, added) = tasks.add(state.tasks, values)
      changed(AppState(..state, tasks: updated_tasks), cli.added(added))
    }
    List(TaskList(criteria)) -> {
      let filter.ListFilter(status, _) = criteria
      let items =
        state.tasks
        |> tasks.visible(filter.resolve(criteria, now, offset))
        |> tasks.sorted_by_id
      unchanged(state, cli.listed(items, status, offset))
    }
    List(ScheduledList(status, scheduled_filter)) -> {
      let resolved = case scheduled_filter {
        filter.AllScheduled -> filter.ResolvedAllScheduled
        filter.ScheduledExact(filter.ScheduledDate(date)) ->
          filter.ResolvedScheduledDate(date)
        filter.ScheduledExact(filter.ScheduledToday) ->
          filter.ResolvedScheduledToday(now)
        filter.ScheduledRange(since, until) ->
          filter.ResolvedScheduledRange(since, until)
      }
      let #(saved_offset, items) = scheduled_list(state, status, resolved)
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
    RunDone(id) ->
      case tasks.complete(state.tasks, id) {
        Ok(#(updated_tasks, completed)) ->
          changed(
            AppState(..state, tasks: updated_tasks),
            cli.completed(completed),
          )
        Error(error) -> unchanged(state, cli.domain_error(error))
      }
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

fn scheduled_list(
  state: AppState,
  status: StatusFilter,
  scheduled_filter: ResolvedScheduledFilter,
) {
  case state.current_schedule {
    None -> #(0, [])
    Some(saved) -> {
      let offset = duration.seconds(saved.utc_offset_seconds)
      let window = filter.scheduled_window(scheduled_filter, offset)
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
        |> list.sort(by: fn(a, b) { invariant.block_compare(a.0, b.0) })
      #(saved.utc_offset_seconds, items)
    }
  }
}

fn unchanged(state: AppState, outcome: Outcome) -> Execution {
  Execution(state, outcome, False)
}

fn changed(state: AppState, outcome: Outcome) -> Execution {
  Execution(state, outcome, True)
}
