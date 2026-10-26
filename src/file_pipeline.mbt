///|
priv struct PendingFile {
  ordinal : Int32
  path : String
  snapshot : @input.Snapshot
  kept_full : Bool
}

///|
priv struct ActiveFile {
  ticket : @compression.BatchTicket
  file : PendingFile
  bytes : Int32
}

///|
priv struct PlannerLane {
  planner : @compression.Planner
  mut active : ActiveFile?
  mut failed : Bool
}

///|
priv struct CollectedFile {
  plan : @compression.PlannedBatch
  file : PendingFile
}

///|
priv struct FilePipeline {
  counter : @metrics.CountSession
  compress : Bool
  accepted : Array[@document.File]
  files : Array[FileStats]
  transforms : Array[Json]
  lanes : Array[PlannerLane]
  completed : Array[(Int32, ProcessedFile)]
  mut next_ordinal : Int32
  mut active_bytes : Int32
  mut creation_disabled : Bool
  mut closed : Bool
}

///|
fn FilePipeline::new(
  counter : @metrics.CountSession,
  compress : Bool,
  accepted : Array[@document.File],
  files : Array[FileStats],
  transforms : Array[Json],
) -> FilePipeline {
  {
    counter,
    compress,
    accepted,
    files,
    transforms,
    lanes: [],
    completed: [],
    next_ordinal: 0,
    active_bytes: 0,
    creation_disabled: false,
    closed: false,
  }
}

///|
fn kept_full_outcome(text : String) -> @compression.Outcome {
  {
    text,
    language: None,
    applied: false,
    reason: Some("kept-full"),
    ranges: [],
  }
}

///|
fn FilePipeline::record(
  self : FilePipeline,
  file : PendingFile,
  outcome : @compression.Outcome?,
) -> Unit {
  self.completed.push(
    (
      file.ordinal,
      process_file_result(
        file.path,
        file.snapshot,
        self.counter.count(file.snapshot.text),
        outcome,
        self.counter,
      ),
    ),
  )
}

///|
fn FilePipeline::record_serial(self : FilePipeline, file : PendingFile) -> Unit {
  let outcome = if !self.compress {
    None
  } else {
    Some(
      if file.kept_full {
        kept_full_outcome(file.snapshot.text)
      } else {
        @compression.compress(file.path, file.snapshot.text)
      },
    )
  }
  self.record(file, outcome)
}

///|
fn FilePipeline::idle_lane(self : FilePipeline) -> Int32? {
  for i in 0..<self.lanes.length() {
    let lane = self.lanes[i]
    if !lane.failed && lane.active is None {
      return Some(i)
    }
  }
  None
}

///|
fn FilePipeline::ready_lane(self : FilePipeline) -> Int32? {
  let mut best : Int32? = None
  let mut ordinal = 2147483647
  for i in 0..<self.lanes.length() {
    if self.lanes[i].active is Some(active) && active.ticket.is_ready() {
      // Retire the oldest completed input; a fast lane cannot starve another
      // completed lane by repeatedly accepting a newer source.
      if best is None || active.file.ordinal < ordinal {
        best = Some(i)
        ordinal = active.file.ordinal
      }
    }
  }
  best
}

///|
fn FilePipeline::has_active(self : FilePipeline) -> Bool {
  self.lanes.any(lane => lane.active is Some(_))
}

///|
async fn FilePipeline::wait_ready_lane(self : FilePipeline) -> Int32 {
  while true {
    if self.ready_lane() is Some(i) {
      return i
    }
    if !self.has_active() {
      raise @compression.PlannerError::Unavailable
    }
    @async.sleep(1)
  } nobreak {
    raise @compression.PlannerError::Unavailable
  }
}

///|
async fn FilePipeline::collect_lane(
  self : FilePipeline,
  i : Int32,
) -> CollectedFile {
  let lane = self.lanes[i]
  guard lane.active is Some(active) else {
    raise @compression.PlannerError::Unavailable
  }
  let plan = active.ticket.collect()
  lane.active = None
  self.active_bytes -= active.bytes
  { plan, file: active.file, }
}

///|
fn FilePipeline::record_collected(
  self : FilePipeline,
  collected : CollectedFile,
) -> Unit raise {
  let results = collected.plan.materialize()
  guard results.length() == 1 else {
    raise @compression.PlannerError::Unavailable
  }
  self.record(collected.file, Some(results[0]))
}

///|
async fn FilePipeline::drain_active(self : FilePipeline) -> Unit {
  while self.has_active() {
    let i = self.wait_ready_lane()
    self.record_collected(self.collect_lane(i))
  }
}

///|
// Three independent single-worker lanes form a rolling window. A completed
// source releases its native slot before the next source is submitted; it need
// not wait for an unrelated slow source from the same former four-file batch.
// Read/screen/quota order stays serial; final records are sorted by ordinal.
async fn FilePipeline::push(
  self : FilePipeline,
  path : String,
  snapshot : @input.Snapshot,
  kept_full : Bool,
) -> Unit {
  if self.closed {
    raise ConfigurationError
  }
  let file = { ordinal: self.next_ordinal, path, snapshot, kept_full, }
  self.next_ordinal += 1
  if !self.compress {
    self.record_serial(file)
    return
  }
  let bytes = snapshot.disk_bytes - snapshot.bom_bytes
  if bytes > 8 * 1024 * 1024 {
    self.drain_active()
    self.record_serial(file)
    return
  }
  if kept_full {
    self.record_serial(file)
    return
  }
  let retired : Array[CollectedFile] = []
  while bytes > 16 * 1024 * 1024 - self.active_bytes {
    retired.push(self.collect_lane(self.wait_ready_lane()))
  }
  let mut idle = self.idle_lane()
  if idle is None {
    if self.ready_lane() is Some(i) {
      retired.push(self.collect_lane(i))
      idle = Some(i)
    } else if !self.creation_disabled && self.lanes.length() < 3 {
      let planner = Some(@compression.Planner::new(workers=1)) catch {
        @compression.PlannerError::Unavailable => {
          self.creation_disabled = true
          None
        }
        err => raise err
      }
      if planner is Some(planner) {
        idle = Some(self.lanes.length())
        self.lanes.push({ planner, active: None, failed: false, })
      }
    }
  }
  if idle is None && self.has_active() {
    let i = self.wait_ready_lane()
    retired.push(self.collect_lane(i))
    idle = Some(i)
  }
  if idle is Some(i) {
    let lane = self.lanes[i]
    let ticket = Some(
      lane.planner.submit([{ path: file.path, text: file.snapshot.text, }]),
    ) catch {
      @compression.PlannerError::Unavailable => {
        lane.failed = true
        self.creation_disabled = true
        lane.planner.close()
        None
      }
      err => raise err
    }
    if ticket is Some(ticket) {
      lane.active = Some({ ticket, file, bytes, })
      self.active_bytes += bytes
    } else {
      self.record_serial(file)
    }
  } else {
    self.record_serial(file)
  }
  // Let the new native job run while the coordinator materializes and counts
  // previously completed inputs. No C result pointer escapes collection.
  for collected in retired {
    self.record_collected(collected)
  }
}

///|
async fn FilePipeline::flush(self : FilePipeline) -> Unit {
  self.drain_active()
  self.completed.sort_by((a, b) => a.0.compare(b.0))
  for (_, result) in self.completed {
    self.accepted.push(result.file)
    self.files.push(result.stats)
    if result.transform is Some(transform) {
      self.transforms.push(transform)
    }
  }
  self.completed.clear()
}

///|
async fn FilePipeline::close(self : FilePipeline) -> Unit {
  if self.closed {
    return
  }
  @async.protect_from_cancel(
    async fn() {
      self.closed = true
      // Start all stops together; one slow parser must not delay cancelling the
      // other lanes. Every child close is itself cancellation protected.
      @async.with_task_group(group => {
        for lane in self.lanes {
          let planner = lane.planner
          group.spawn_bg(async fn() { planner.close() })
        }
      })
      self.lanes.clear()
      self.active_bytes = 0
      self.completed.clear()
    },
    resume_on_cancel=true,
  )
}
