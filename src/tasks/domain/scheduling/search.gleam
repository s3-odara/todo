import tasks/domain/scheduling/timeline.{type AbsoluteInterval}

/// Immutable inputs shared by every stage of a scheduling search.
pub type SearchSpace {
  SearchSpace(
    projected: List(AbsoluteInterval),
    planning_start: Int,
    utc_offset_seconds: Int,
  )
}
