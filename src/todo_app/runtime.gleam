import gleam/time/calendar
import tasks/domain/filter.{ListFilter}
import todo_app/cli.{type Command, type Outcome, Add, Help, List, RunDone}
import todo_app/service
import todo_app/store.{type Store}

/// Pure application runner: adapters supply a parsed command and configured Store.
pub fn run(command: Command, store: Store, today: calendar.Date) -> Outcome {
  case command {
    Help -> cli.help()
    Add(values) -> service.add(store, values) |> service_outcome(cli.added)
    List(filter) -> {
      let ListFilter(status, _) = filter
      service.list(store, filter, today)
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
