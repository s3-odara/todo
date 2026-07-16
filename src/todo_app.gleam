import argv
import envoy
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/time/calendar
import gleam/time/timestamp
import tasks/runtime as process
import tasks/store/file
import todo_app/cli.{type Command, type Outcome, Help, Outcome}
import todo_app/runtime
import todo_app/store.{Store}
import todo_app/store/path

pub fn main() -> Nil {
  let args = argv.load().arguments
  // Help and grammar errors do not depend on persistence configuration.
  case cli.parse(args, calendar.local_offset()) {
    Ok(Help) -> emit(cli.help())
    Ok(command) -> run_with_path(command)
    Error(message) -> emit(cli.grammar_error(message))
  }
}

fn run_with_path(command: Command) -> Nil {
  case
    path.resolve(
      environment("TODO_FILE"),
      environment("XDG_DATA_HOME"),
      environment("HOME"),
    )
  {
    Error(message) -> emit(cli.persistence_error(message))
    Ok(filename) ->
      emit(runtime.run(
        command,
        Store(fn() { file.load(filename) }, fn(tasks) {
          file.save(filename, tasks)
        }),
        local_clock,
      ))
  }
}

fn local_clock() {
  #(timestamp.system_time(), calendar.local_offset())
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
