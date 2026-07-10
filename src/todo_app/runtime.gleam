import todo_app/cli.{type Command, type Outcome, Add, Help, List, RunDone}
import todo_app/service
import todo_app/store.{type Store}

/// Pure application runner: adapters supply a parsed command and configured Store.
pub fn run(command: Command, store: Store) -> Outcome {
  case command {
    Help -> cli.help()
    Add(request) -> service.add(store, request) |> service_outcome(cli.added)
    List(request) ->
      service.list(store, request)
      |> service_outcome(fn(items) { cli.listed(items, request.include_all) })
    RunDone(request) ->
      service.done(store, request) |> service_outcome(cli.completed)
  }
}

fn service_outcome(result, on_success) {
  case result {
    Ok(value) -> on_success(value)
    Error(error) -> cli.service_error(error)
  }
}
