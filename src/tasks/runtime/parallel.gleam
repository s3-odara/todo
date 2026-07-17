import gleam/erlang/process
import gleam/int
import gleam/list

@external(erlang, "tasks_runtime_ffi", "schedulers_online")
fn runtime_schedulers_online() -> Int

pub fn online_scheduler_count() -> Int {
  int.max(runtime_schedulers_online(), 1)
}

pub fn worker_count(online: Int, useful_work: Int) -> Int {
  case useful_work <= 0 {
    True -> 0
    False -> int.min(int.max(online, 1), useful_work)
  }
}

/// Evaluate contiguous chunks in parallel and merge results in receive order.
pub fn map_chunks_reduce(
  items: List(item),
  initial: result,
  evaluate_chunk: fn(List(item)) -> result,
  merge: fn(result, result) -> result,
) -> result {
  let count = list.length(items)
  let workers = worker_count(online_scheduler_count(), count)
  case workers <= 1 {
    True -> merge(initial, evaluate_chunk(items))
    False -> {
      let chunk_size = { count + workers - 1 } / workers
      let chunks = list.sized_chunk(items, into: chunk_size)
      let results = process.new_subject()
      chunks
      |> list.each(fn(chunk) {
        process.spawn(fn() { process.send(results, evaluate_chunk(chunk)) })
        Nil
      })
      collect(results, list.length(chunks), initial, merge)
    }
  }
}

fn collect(subject, remaining, value, merge) {
  case remaining {
    0 -> value
    _ ->
      collect(
        subject,
        remaining - 1,
        merge(value, process.receive_forever(subject)),
        merge,
      )
  }
}
