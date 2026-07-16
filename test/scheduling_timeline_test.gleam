import gleeunit/should
import tasks/domain/scheduling/model.{ScheduleBlock}
import tasks/domain/scheduling/timeline.{AbsoluteInterval}

fn block(task_id, start, end) {
  ScheduleBlock(task_id, start, end)
}

pub fn canonical_free_intervals_are_carved_in_one_pass_test() {
  timeline.free_intervals([AbsoluteInterval(0, 100)], [])
  |> should.equal([AbsoluteInterval(0, 100)])
  timeline.free_intervals([AbsoluteInterval(0, 100)], [
    block(1, 0, 20),
    block(2, 40, 60),
    block(3, 80, 100),
  ])
  |> should.equal([AbsoluteInterval(20, 40), AbsoluteInterval(60, 80)])
  timeline.free_intervals([AbsoluteInterval(0, 20), AbsoluteInterval(40, 100)], [
    block(1, 0, 20),
    block(2, 50, 70),
  ])
  |> should.equal([AbsoluteInterval(40, 50), AbsoluteInterval(70, 100)])
}

pub fn empty_or_fully_occupied_timeline_has_no_free_intervals_test() {
  timeline.free_intervals([], []) |> should.equal([])
  timeline.free_intervals([AbsoluteInterval(-120, -60)], [block(1, -120, -60)])
  |> should.equal([])
}
