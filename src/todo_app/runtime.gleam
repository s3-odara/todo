import gleam/time/calendar
import tasks/domain/filter.{ListFilter}
import todo_app/cli.{type Command, type Outcome, Add, Help, List, RunDone}
import todo_app/service
import todo_app/store.{type Store}

/// Application boundary: adapters supply persistence and the local calendar clock.
pub fn run(
  command: Command,
  store: Store,
  local_today: fn() -> calendar.Date,
) -> Outcome {
  case command {
    Help -> cli.help()
    Add(values) -> service.add(store, values) |> service_outcome(cli.added)
    List(criteria) -> {
      let ListFilter(status, _) = criteria
      // Read the clock only for list; lower layers receive absolute criteria.
      let resolved = filter.resolve(criteria, local_today())
      service.list(store, resolved)
      |> service_outcome(fn(items) { cli.listed(items, status) })
    }
    RunDone(id) -> service.done(store, id) |> service_outcome(cli.completed)
  }
}

fn service_outcome(result, on_success) {
  case result {
    Ok(value) -> on_success(value)
    Error(service.Persisted(message)) -> cli.persistence_error(message)
    Error(service.Domain(error)) -> cli.domain_error(error)
  }
}
