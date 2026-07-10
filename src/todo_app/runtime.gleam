import todo_app/cli.{type Outcome, Add, Help, List, RunDone}
import todo_app/service
import todo_app/store.{type Store}

/// Pure application runner: adapters supply argv and an already configured Store.
pub fn run(args: List(String), store: Store) -> Outcome {
  case cli.parse(args) {
    Error(message) -> cli.grammar_error(message)
    Ok(Help) -> cli.help()
    Ok(Add(request)) -> service.add(store, request) |> add_outcome
    Ok(List(request)) ->
      service.list(store, request) |> list_outcome(request.include_all)
    Ok(RunDone(request)) -> service.done(store, request) |> done_outcome
  }
}

fn add_outcome(result) {
  case result {
    Ok(value) -> cli.added(value)
    Error(error) -> cli.service_error(error)
  }
}

fn done_outcome(result) {
  case result {
    Ok(value) -> cli.completed(value)
    Error(error) -> cli.service_error(error)
  }
}

fn list_outcome(result, all) {
  case result {
    Ok(value) -> cli.listed(value, all)
    Error(error) -> cli.service_error(error)
  }
}
