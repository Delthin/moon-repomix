///|
priv struct PendingFile {
  path : String
  snapshot : @input.Snapshot
  kept_full : Bool
}

///|
priv struct ActiveBatch {
  ticket : @compression.BatchTicket
  files : Array[PendingFile]
}

///|
priv struct CollectedBatch {
  plan : @compression.PlannedBatch
  files : Array[PendingFile]
}

///|
priv struct FilePipeline {
  counter : @metrics.CountSession
  compress : Bool
  accepted : Array[@document.File]
  files : Array[FileStats]
  transforms : Array[Json]
  mut pending : Array[PendingFile]
  mut pending_bytes : Int32
  mut active : ActiveBatch?
  mut planner_attempted : Bool
  mut planner : @compression.Planner?
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
    pending: [],
    pending_bytes: 0,
    active: None,
    planner_attempted: false,
    planner: None,
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
  record_file_result(
    file.path,
    file.snapshot,
    self.counter.count(file.snapshot.text),
    outcome,
    self.counter,
    self.accepted,
    self.files,
    self.transforms,
  )
}

///|
// Reads and full screening remain ordered. An active window and one lookahead
// window each hold at most four snapshots / 16MiB source UTF-8. Completed wires
// are detached before their materialization so the next native batch can run;
// C-owned inputs retain the process-global four-input / 16MiB bound.
async fn FilePipeline::push(
  self : FilePipeline,
  path : String,
  snapshot : @input.Snapshot,
  kept_full : Bool,
) -> Unit {
  let bytes = snapshot.disk_bytes - snapshot.bom_bytes
  if self.compress {
    if bytes > 8 * 1024 * 1024 {
      self.flush()
    } else if bytes > 16 * 1024 * 1024 - self.pending_bytes {
      self.start_pending()
    }
  }
  let file = { path, snapshot, kept_full, }
  if !self.compress || bytes > 8 * 1024 * 1024 {
    self.record_serial(file)
    return
  }
  self.pending.push(file)
  self.pending_bytes += bytes
  if self.pending.length() == 4 || self.pending_bytes == 16 * 1024 * 1024 {
    self.start_pending()
  }
}

///|
async fn FilePipeline::collect_active(self : FilePipeline) -> CollectedBatch? {
  guard self.active is Some(batch) else { return None }
  self.active = None
  // collect owns every returned wire before releasing the native batch slots.
  let plan = batch.ticket.collect()
  Some({ plan, files: batch.files, })
}

///|
fn FilePipeline::record_collected(
  self : FilePipeline,
  batch : CollectedBatch,
) -> Unit raise {
  let results = batch.plan.materialize()
  let mut result_index = 0
  for file in batch.files {
    let outcome = if file.kept_full {
      kept_full_outcome(file.snapshot.text)
    } else {
      if result_index >= results.length() {
        raise @compression.PlannerError::Unavailable
      }
      let result = results[result_index]
      result_index += 1
      result
    }
    record_file_result(
      file.path,
      file.snapshot,
      self.counter.count(file.snapshot.text),
      Some(outcome),
      self.counter,
      self.accepted,
      self.files,
      self.transforms,
    )
  }
  if result_index != results.length() {
    raise @compression.PlannerError::Unavailable
  }
}

///|
// Returns serial fallbacks without publishing them: they must stay after the
// previously collected batch even when no native job can be submitted.
async fn FilePipeline::submit_pending(
  self : FilePipeline,
) -> Array[PendingFile] {
  let files = self.pending
  self.pending = []
  self.pending_bytes = 0
  let sources : Array[@compression.Source] = []
  for file in files {
    if !file.kept_full {
      sources.push({ path: file.path, text: file.snapshot.text, })
    }
  }
  if sources.is_empty() {
    return files
  }
  if !self.planner_attempted {
    self.planner_attempted = true
    self.planner = Some(@compression.Planner::new(workers=3)) catch {
      @compression.PlannerError::Unavailable => None
      err => raise err
    }
  }
  guard self.planner is Some(planner) else { return files }
  let ticket = planner.submit(sources) catch {
    // Submission stages all native sources before any worker starts a job.
    @compression.PlannerError::Unavailable => {
      self.planner = None
      planner.close()
      return files
    }
    err => raise err
  }
  self.active = Some({ ticket, files, })
  []
}

///|
async fn FilePipeline::start_pending(self : FilePipeline) -> Unit {
  if self.pending.is_empty() {
    return
  }
  let previous = self.collect_active()
  // Restart native work before materializing or counting previous results.
  let serial = self.submit_pending()
  if previous is Some(batch) {
    self.record_collected(batch)
  }
  for file in serial {
    self.record_serial(file)
  }
}

///|
async fn FilePipeline::finish_active(self : FilePipeline) -> Unit {
  if self.collect_active() is Some(batch) {
    self.record_collected(batch)
  }
}

///|
async fn FilePipeline::flush(self : FilePipeline) -> Unit {
  self.start_pending()
  self.finish_active()
}

///|
async fn FilePipeline::close(self : FilePipeline) -> Unit {
  if self.planner is Some(planner) {
    self.planner = None
    planner.close()
  }
  self.active = None
  self.pending.clear()
  self.pending_bytes = 0
}
