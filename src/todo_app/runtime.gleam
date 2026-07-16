import gleam/option.{None, Some}
import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/filter.{
  ScheduledExact, ScheduledList, ScheduledToday, TaskList,
}
import tasks/domain/scheduling/scheduler
import todo_app/cli.{
  type Command, type Outcome, Add, AvailabilityList, GenerateSchedule, Help,
  List, MutateAvailability, RunDone,
}
import todo_app/service
import todo_app/store.{type Store}

/// Application boundary: adapters supply persistence and one coherent clock sample.
pub fn run(
  command: Command,
  store: Store,
  clock: fn() -> #(Timestamp, Duration),
) -> Outcome {
  case command {
    Help -> cli.help()
    Add(values) -> service.add(store, values) |> service_outcome(cli.added)
    List(TaskList(criteria)) -> {
      let filter.ListFilter(status, _) = criteria
      let #(now, offset) = clock()
      let resolved = filter.resolve(criteria, now, offset)
      service.list(store, resolved)
      |> service_outcome(fn(items) { cli.listed(items, status, offset) })
    }
    List(ScheduledList(status, scheduled_filter)) -> {
      let now = case scheduled_filter {
        ScheduledExact(ScheduledToday) -> {
          let #(current, _) = clock()
          Some(current)
        }
        _ -> None
      }
      service.scheduled_list(store, status, scheduled_filter, now)
      |> service_outcome(cli.scheduled_listed)
    }
    GenerateSchedule -> {
      let #(now, offset) = clock()
      service.generate_schedule(store, scheduler.context(now, offset))
      |> service_outcome(cli.schedule_generated)
    }
    RunDone(id) -> service.done(store, id) |> service_outcome(cli.completed)
    AvailabilityList ->
      service.availability_list(store)
      |> service_outcome(cli.availability_listed)
    MutateAvailability(mutation) ->
      service.mutate_availability(store, mutation)
      |> service_outcome(fn(_) { cli.availability_updated() })
  }
}

fn service_outcome(result, on_success) {
  case result {
    Ok(value) -> on_success(value)
    Error(service.Persisted(message)) -> cli.persistence_error(message)
    Error(service.Domain(error)) -> cli.domain_error(error)
    Error(service.Scheduling(error)) -> cli.scheduling_error(error)
  }
}
