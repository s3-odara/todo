import gleam/time/duration.{type Duration}
import gleam/time/timestamp.{type Timestamp}
import tasks/domain/filter.{ListFilter}
import todo_app/cli.{type Command, type Outcome, Add, Help, List, RunDone}
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
    List(criteria) -> {
      let ListFilter(status, _) = criteria
      let #(now, offset) = clock()
      let resolved = filter.resolve(criteria, now, offset)
      service.list(store, resolved)
      |> service_outcome(fn(items) { cli.listed(items, status, offset) })
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
