import argv
import envoy
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import tasks/runtime as process
import tasks/store/file
import todo_app/cli.{type Outcome, Add, Help, Outcome, RunDone}
import todo_app/runtime
import todo_app/service
import todo_app/store.{Store}
import todo_app/store/path

pub fn main() -> Nil {
  let args = argv.load().arguments
  // Help is parsed before this boundary is constructed, so it never reads env.
  case cli.parse(args) {
    Ok(Help) -> emit(cli.help())
    Ok(Add(request)) ->
      case service.validate_add(request) {
        Error(error) -> emit(cli.service_error(error))
        Ok(_) -> run_with_path(args)
      }
    Ok(RunDone(request)) ->
      case service.validate_done(request) {
        Error(error) -> emit(cli.service_error(error))
        Ok(_) -> run_with_path(args)
      }
    Ok(_) -> run_with_path(args)
    Error(message) -> emit(cli.grammar_error(message))
  }
}

fn run_with_path(args: List(String)) -> Nil {
  case
    path.resolve(
      environment("TODO_FILE"),
      environment("XDG_DATA_HOME"),
      environment("HOME"),
    )
  {
    Error(message) -> emit(cli.grammar_error(message) |> path_error)
    Ok(filename) ->
      emit(runtime.run(
        args,
        Store(fn() { file.load(filename) }, fn(tasks) {
          file.save(filename, tasks)
        }),
      ))
  }
}

fn path_error(outcome: Outcome) -> Outcome {
  let Outcome(_, stdout, stderr) = outcome
  Outcome(1, stdout, stderr)
}

fn environment(name: String) {
  case envoy.get(name) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn emit(outcome: Outcome) -> Nil {
  let Outcome(code, stdout, stderr) = outcome
  list.each(stdout, io.println)
  list.each(stderr, io.println_error)
  process.halt(code)
}
