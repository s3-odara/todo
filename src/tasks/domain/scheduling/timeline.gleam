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

pub type TimelineError {
  SearchSpaceTooLarge
  InvalidCalendarRange
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
        [],
        0,
      )
    }
  }
}

fn project_dates(value, date, last_date, lower, upper, offset, acc, count) {
  case calendar.naive_date_compare(date, last_date) {
    order.Gt -> Ok(acc |> list.reverse |> merge_projected([]) |> list.reverse)
    _ -> {
      let intervals = availability.effective(value, date)
      let additions =
        intervals
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
      let next_count = count + list.length(additions)
      case next_count > projected_interval_limit {
        True -> Error(SearchSpaceTooLarge)
        False ->
          case calendar.naive_date_compare(date, last_date) {
            order.Eq ->
              Ok(
                list.append(list.reverse(additions), acc)
                |> list.reverse
                |> merge_projected([])
                |> list.reverse,
              )
            _ -> {
              use next <- result.try(
                local_time.next_date(date)
                |> result.map_error(fn(_) { InvalidCalendarRange }),
              )
              project_dates(
                value,
                next,
                last_date,
                lower,
                upper,
                offset,
                list.append(list.reverse(additions), acc),
                next_count,
              )
            }
          }
      }
    }
  }
}

/// Local midnight plus a local minute, converted through the fixed offset.
pub fn local_minute_seconds(
  date: calendar.Date,
  minute: Int,
  offset: Int,
) -> Int {
  let midnight =
    timestamp.from_calendar(
      date,
      calendar.TimeOfDay(0, 0, 0, 0),
      duration.seconds(offset),
    )
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(midnight)
  seconds + minute * 60
}

/// Free portions of projected availability after subtracting canonical blocks.
pub fn free_intervals(
  projected: List(AbsoluteInterval),
  blocks: List(ScheduleBlock),
) -> List(AbsoluteInterval) {
  projected
  |> list.flat_map(fn(interval) { subtract_blocks(interval, blocks) })
}

fn subtract_blocks(
  interval: AbsoluteInterval,
  blocks: List(ScheduleBlock),
) -> List(AbsoluteInterval) {
  let relevant =
    blocks
    |> list.filter_map(fn(block) {
      let start = seconds(block.start)
      let end = seconds(block.end)
      case end > interval.start && start < interval.end {
        True -> Ok(AbsoluteInterval(start, end))
        False -> Error(Nil)
      }
    })
    |> list.sort(by: interval_compare)
  carve(relevant, interval.start, interval.end, []) |> list.reverse
}

fn carve(
  blocks: List(AbsoluteInterval),
  cursor: Int,
  end: Int,
  acc: List(AbsoluteInterval),
) -> List(AbsoluteInterval) {
  case blocks {
    [] ->
      case cursor < end {
        True -> [AbsoluteInterval(cursor, end), ..acc]
        False -> acc
      }
    [block, ..rest] -> {
      let clipped_start = int.max(cursor, block.start)
      let next_cursor = int.max(cursor, block.end)
      case clipped_start > cursor {
        True ->
          carve(rest, next_cursor, end, [
            AbsoluteInterval(cursor, clipped_start),
            ..acc
          ])
        False -> carve(rest, next_cursor, end, acc)
      }
    }
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

fn interval_compare(a: AbsoluteInterval, b: AbsoluteInterval) -> order.Order {
  case int.compare(a.start, b.start) {
    order.Eq -> int.compare(a.end, b.end)
    other -> other
  }
}

fn seconds(value) -> Int {
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(value)
  seconds
}
