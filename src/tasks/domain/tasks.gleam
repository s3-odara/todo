import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/string
import gleam/time/calendar
import tasks/domain/due
import tasks/domain/filter.{
  type DueFilter, type ListFilter, type StatusFilter, AllStatuses, DoneOnly,
  Exact, ListFilter, Overdue, PendingOnly, Range, Today,
}
import tasks/domain/model.{
  type TaskError, type Todo, type ValidatedAdd, AlreadyDone, Done, NotFound,
  Pending, Todo, ValidatedAdd,
}

// BEAM integers are arbitrary precision, so max + 1 cannot overflow.
fn next_id(todos: List(Todo)) -> Int {
  todos
  |> list.fold(0, fn(current, task) { int.max(current, task.id) })
  |> int.add(1)
}

pub fn add(todos: List(Todo), values: ValidatedAdd) -> #(List(Todo), Todo) {
  let ValidatedAdd(title, estimate, priority, due) = values
  let added = Todo(next_id(todos), title, estimate, priority, due, Pending)
  #([added, ..todos], added)
}

pub fn complete(
  todos: List(Todo),
  wanted: Int,
) -> Result(#(List(Todo), Todo), TaskError) {
  case list.find(todos, fn(task) { task.id == wanted }) {
    Error(_) -> Error(NotFound)
    Ok(Todo(status: Done, ..)) -> Error(AlreadyDone)
    Ok(task) -> {
      let completed = Todo(..task, status: Done)
      // IDs created by the app are unique; replacing by ID keeps the update clear.
      let updated =
        list.map(todos, fn(current) {
          case current.id == wanted {
            True -> completed
            False -> current
          }
        })
      Ok(#(updated, completed))
    }
  }
}

pub fn visible_sorted(
  todos: List(Todo),
  filter: ListFilter,
  today: calendar.Date,
) -> List(Todo) {
  let ListFilter(status, due_filter) = filter
  // Keep display order independent of mutable task metadata.
  todos
  |> list.filter(fn(task) {
    status_matches(task, status) && due_matches(task, due_filter, today)
  })
  |> list.sort(by: fn(a, b) { int.compare(a.id, b.id) })
}

fn status_matches(task: Todo, filter: StatusFilter) -> Bool {
  case filter {
    PendingOnly -> task.status == Pending
    DoneOnly -> task.status == Done
    AllStatuses -> True
  }
}

fn due_matches(
  task: Todo,
  filter: Option(DueFilter),
  today: calendar.Date,
) -> Bool {
  case filter, task.due {
    None, _ -> True
    Some(_), None -> False
    Some(filter), Some(stored) -> {
      // Due values are app-owned canonical values; compare their date component.
      let assert Ok(date) =
        due.parse_date(string.slice(stored.canonical, 0, 10))
      date_matches(date, filter, today)
    }
  }
}

fn date_matches(
  date: calendar.Date,
  filter: DueFilter,
  today: calendar.Date,
) -> Bool {
  case filter {
    Exact(wanted) -> calendar.naive_date_compare(date, wanted) == Eq
    Today -> calendar.naive_date_compare(date, today) == Eq
    Overdue -> calendar.naive_date_compare(date, today) == Lt
    Range(since, until) -> {
      let after_start = case since {
        None -> True
        Some(start) -> calendar.naive_date_compare(date, start) != Lt
      }
      let before_end = case until {
        None -> True
        Some(end) -> calendar.naive_date_compare(date, end) != Gt
      }
      after_start && before_end
    }
  }
}
