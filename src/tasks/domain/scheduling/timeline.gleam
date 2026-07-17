import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import tasks/domain/availability
import tasks/domain/local_time
import tasks/domain/scheduling/model.{type ScheduleBlock}

pub const projected_interval_limit = 10_000

pub type AbsoluteInterval {
  AbsoluteInterval(start: Int, end: Int)
}

/// Immutable inputs shared by every stage of a scheduling search.
pub type SearchSpace {
  SearchSpace(
    projected: List(AbsoluteInterval),
    planning_start: Int,
    utc_offset_seconds: Int,
  )
}

pub type TimelineError {
  SearchSpaceTooLarge
  InvalidCalendarRange
}

type ProjectionState {
  ProjectionState(reversed: List(AbsoluteInterval), additions: Int)
}

/// Project effective local availability lazily by date, clipping at both ends.
pub fn project(
  value: availability.Availability,
  planning_start: Int,
  horizon: Int,
  utc_offset_seconds: Int,
) -> Result(List(AbsoluteInterval), TimelineError) {
  case horizon <= planning_start {
    True -> Ok([])
    False -> {
      let offset = duration.seconds(utc_offset_seconds)
      let #(first_date, _) =
        timestamp.to_calendar(
          timestamp.from_unix_seconds(planning_start),
          offset,
        )
      let #(last_date, _) =
        timestamp.to_calendar(timestamp.from_unix_seconds(horizon), offset)
      project_dates(
        value,
        first_date,
        last_date,
        planning_start,
        horizon,
        utc_offset_seconds,
        ProjectionState([], 0),
      )
    }
  }
}

fn project_dates(value, date, last_date, lower, upper, offset, state) {
  let additions = project_date(value, date, lower, upper, offset)
  let ProjectionState(reversed, count) = state
  let next =
    ProjectionState(
      list.append(list.reverse(additions), reversed),
      count + list.length(additions),
    )
  case next.additions > projected_interval_limit {
    True -> Error(SearchSpaceTooLarge)
    False ->
      case calendar.naive_date_compare(date, last_date) {
        order.Eq -> Ok(finish_projection(next))
        _ -> {
          use following <- result.try(
            local_time.next_date(date)
            |> result.map_error(fn(_) { InvalidCalendarRange }),
          )
          project_dates(value, following, last_date, lower, upper, offset, next)
        }
      }
  }
}

fn project_date(value, date, lower, upper, offset) {
  availability.effective(value, date)
  |> list.filter_map(fn(interval) {
    let start = local_minute_seconds(date, interval.from, offset)
    let end = local_minute_seconds(date, interval.to, offset)
    let clipped_start = int.max(start, lower)
    let clipped_end = int.min(end, upper)
    case clipped_start < clipped_end {
      True -> Ok(AbsoluteInterval(clipped_start, clipped_end))
      False -> Error(Nil)
    }
  })
}

fn finish_projection(state: ProjectionState) -> List(AbsoluteInterval) {
  state.reversed
  |> list.reverse
  |> merge_projected([])
  |> list.reverse
}

/// Local midnight plus a local minute, converted through the fixed offset.
fn local_minute_seconds(date: calendar.Date, minute: Int, offset: Int) -> Int {
  let midnight =
    timestamp.from_calendar(
      date,
      calendar.TimeOfDay(0, 0, 0, 0),
      duration.seconds(offset),
    )
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(midnight)
  seconds + minute * 60
}

/// Return free half-open intervals in O(P+B).
///
/// Projected intervals must be ordered, merged, and disjoint. Blocks must be
/// canonical, non-overlapping, and each fully contained in one projected interval.
pub fn free_intervals(
  projected: List(AbsoluteInterval),
  blocks: List(ScheduleBlock),
) -> List(AbsoluteInterval) {
  free(projected, blocks, []) |> list.reverse
}

fn free(
  projected: List(AbsoluteInterval),
  blocks: List(ScheduleBlock),
  reversed: List(AbsoluteInterval),
) -> List(AbsoluteInterval) {
  case projected {
    [] -> reversed
    [interval, ..rest] -> {
      let #(remaining, next) = carve(interval, blocks, interval.start, reversed)
      free(rest, remaining, next)
    }
  }
}

fn carve(
  interval: AbsoluteInterval,
  blocks: List(ScheduleBlock),
  cursor: Int,
  reversed: List(AbsoluteInterval),
) -> #(List(ScheduleBlock), List(AbsoluteInterval)) {
  case blocks {
    [] -> #(blocks, add_gap(cursor, interval.end, reversed))
    [block, ..rest] -> {
      let start = block.start_seconds
      let end = block.end_seconds
      case start >= interval.end {
        True -> #(blocks, add_gap(cursor, interval.end, reversed))
        False -> carve(interval, rest, end, add_gap(cursor, start, reversed))
      }
    }
  }
}

fn add_gap(start, end, reversed) {
  case start < end {
    True -> [AbsoluteInterval(start, end), ..reversed]
    False -> reversed
  }
}

fn merge_projected(
  values: List(AbsoluteInterval),
  acc: List(AbsoluteInterval),
) -> List(AbsoluteInterval) {
  case values, acc {
    [], _ -> acc
    [next, ..rest], [] -> merge_projected(rest, [next])
    [next, ..rest], [current, ..previous] ->
      case next.start <= current.end {
        True ->
          merge_projected(rest, [
            AbsoluteInterval(current.start, int.max(current.end, next.end)),
            ..previous
          ])
        False -> merge_projected(rest, [next, current, ..previous])
      }
  }
}
