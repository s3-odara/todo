import todo_app/cli.{type Outcome, Add, Help, List, RunDone}
import todo_app/service
import todo_app/store.{type Store}

/// Pure application runner: adapters supply argv and an already configured Store.
pub fn run(args: List(String), store: Store) -> Outcome {
  case cli.parse(args) {
    Error(message) -> cli.grammar_error(message)
    Ok(Help) -> cli.help()
    Ok(Add(request)) ->
      service.add(store, request) |> service_outcome(cli.added)
    Ok(List(request)) ->
      service.list(store, request)
      |> service_outcome(fn(items) { cli.listed(items, request.include_all) })
    Ok(RunDone(request)) ->
      service.done(store, request) |> service_outcome(cli.completed)
  }
}

fn service_outcome(result, on_success) {
  case result {
    Ok(value) -> on_success(value)
    Error(error) -> cli.service_error(error)
  }
}
