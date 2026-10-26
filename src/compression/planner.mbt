///|
/// Input text is already read and security-scanned by the caller.
pub(all) struct Source {
  path : String
  text : String
} derive(Debug, Eq)

///|
pub(all) suberror PlannerError {
  InvalidWorkers
  BatchLimit
  Busy
  Closed
  Finished
  Unavailable
} derive(Debug)

///|
pub extend Source with Eq::{equal, not_equal}

///|
pub extend Source with Debug::{to_repr}

///|
pub extend PlannerError with Debug::{to_repr}

///|
#external
priv type PoolHandle

///|
extern "c" fn pool_new(workers : Int32) -> PoolHandle = "moon_repomix_pool_new"

///|
#borrow(pool)
extern "c" fn pool_available(pool : PoolHandle) -> Bool = "moon_repomix_pool_available"

///|
#borrow(pool, source)
extern "c" fn pool_add(
  pool : PoolHandle,
  language : Int32,
  source : Bytes,
) -> Bool = "moon_repomix_pool_add"

///|
#borrow(pool)
extern "c" fn pool_start(pool : PoolHandle) -> Bool = "moon_repomix_pool_start"

///|
#borrow(pool)
extern "c" fn pool_done(pool : PoolHandle) -> Bool = "moon_repomix_pool_done"

///|
#borrow(pool)
extern "c" fn pool_result(pool : PoolHandle, index : Int32) -> Bytes = "moon_repomix_pool_result"

///|
#borrow(pool)
extern "c" fn pool_release(pool : PoolHandle) -> Unit = "moon_repomix_pool_release"

///|
#borrow(pool)
extern "c" fn pool_stop(pool : PoolHandle) -> Unit = "moon_repomix_pool_stop"

///|
#borrow(pool)
extern "c" fn pool_live(pool : PoolHandle) -> Int32 = "moon_repomix_pool_live"

///|
#borrow(pool)
extern "c" fn pool_dispose(pool : PoolHandle) -> Unit = "moon_repomix_pool_dispose"

///|
/// Reusable OS-thread planner. Explicitly close after the final batch.
struct Planner {
  handle : PoolHandle
  mut busy : Bool
  mut closed : Bool
}

///|
priv struct Prepared {
  source : Source
  // None entries are exact unsupported/oversize fallbacks, never native jobs.
  native : (Int32, String, Bytes)?
  fallback : Outcome?
}

///|
/// Retains the planner and an immutable snapshot of the submitted sources.
struct BatchTicket {
  planner : Planner
  inputs : Array[Prepared]
  mut finishing : Bool
  mut finished : Bool
}

///|
/// Workers must be 1..4. Thread/allocation failure raises Unavailable.
pub fn Planner::new(workers~ : Int32 = 2) -> Planner raise PlannerError {
  if workers < 1 || workers > 4 {
    raise InvalidWorkers
  }
  let handle = pool_new(workers)
  if !pool_available(handle) {
    raise Unavailable
  }
  { handle, busy: false, closed: false, }
}

///|
/// Copy and enqueue before returning; at most four sources and 16 MiB eligible
/// UTF-8 per batch. One outstanding ticket per planner, including an empty batch.
/// Unsupported/over-8-MiB sources retain serial fallback semantics without a C copy.
pub fn Planner::submit(
  self : Planner,
  sources : Array[Source],
) -> BatchTicket raise PlannerError {
  if self.closed {
    raise Closed
  }
  if self.busy {
    raise Busy
  }
  if sources.length() > 4 {
    raise BatchLimit
  }
  let inputs : Array[Prepared] = []
  let mut bytes = 0
  for source in sources {
    match detect(source.path) {
      None =>
        inputs.push({
          source,
          native: None,
          fallback: Some(fallback(source.text, None, "unsupported")),
        })
      Some((id, language)) => {
        let encoded = @utf8.encode(source.text)
        if encoded.length() > 8 * 1024 * 1024 {
          inputs.push({
            source,
            native: None,
            fallback: Some(
              fallback(source.text, Some(language), "resource-limit"),
            ),
          })
        } else {
          bytes += encoded.length()
          if bytes > 16 * 1024 * 1024 {
            raise BatchLimit
          }
          inputs.push({
            source,
            native: Some((id, language, encoded)),
            fallback: None,
          })
        }
      }
    }
  }
  // No task runs until every C-owned copy has been staged successfully.
  for input in inputs {
    if input.native is Some((id, _, encoded)) {
      if !pool_add(self.handle, id, encoded) {
        pool_release(self.handle)
        raise Unavailable
      }
    }
  }
  if !pool_start(self.handle) {
    pool_release(self.handle)
    raise Unavailable
  }
  self.busy = true
  { planner: self, inputs, finishing: false, finished: false, }
}

///|
/// Wait without blocking the event loop; return outcomes in input order.
/// Cancellation closes this planner and joins all workers before propagating.
pub async fn BatchTicket::finish(self : BatchTicket) -> Array[Outcome] {
  if self.finished {
    raise Finished
  }
  if self.finishing {
    raise Busy
  }
  self.finishing = true
  let planner = self.planner
  defer {
    self.finishing = false
  }
  errdefer {
    @async.protect_from_cancel(
      async fn() { planner.close() },
      resume_on_cancel=true,
    )
    self.finished = true
  }
  if @async.is_being_cancelled() {
    @async.sleep(0)
  }
  while !planner.closed && !pool_done(planner.handle) {
    @async.sleep(1)
  }
  if planner.closed {
    raise Closed
  }
  let results : Array[Outcome] = []
  let mut index = 0
  for input in self.inputs {
    match input.native {
      None => {
        guard input.fallback is Some(result) else { abort("missing fallback") }
        results.push(result)
      }
      Some((id, language, source)) => {
        let wire = pool_result(planner.handle, index)
        if wire.length() < 4 || u32(wire, 0) == 5 {
          raise Unavailable
        }
        results.push(
          outcome_from_plan(input.source.text, id, language, source, wire),
        )
        index += 1
      }
    }
  }
  pool_release(planner.handle)
  planner.busy = false
  self.finished = true
  results
}

///|
pub async fn Planner::compress(
  self : Planner,
  sources : Array[Source],
) -> Array[Outcome] {
  self.submit(sources).finish()
}

///|
/// Idempotent cancellation-protected stop, async drain, then join and release.
/// A pending ticket becomes Closed; a cancelled finish always propagates cancellation.
pub async fn Planner::close(self : Planner) -> Unit {
  @async.protect_from_cancel(async fn() {
    self.closed = true
    pool_stop(self.handle)
    while pool_live(self.handle) != 0 {
      @async.sleep(1)
    }
    pool_dispose(self.handle)
    self.busy = false
  })
}
