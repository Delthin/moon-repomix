///|
priv struct PendingFile {
  path : String
  snapshot : @input.Snapshot
  kept_full : Bool
  original_tokens : Int32
}

///|
priv struct ActiveBatch {
  ticket : @compression.BatchTicket
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
    file.original_tokens,
    outcome,
    self.counter,
    self.accepted,
    self.files,
    self.transforms,
  )
}

///|
// Metered reads and complete screening remain ordered on the caller. One
// bounded lookahead window can be filled while the preceding C batch runs.
// Each retained window has at most four files / 16MiB of source UTF-8; C-owned
// active copies retain their stricter process-global four-input / 16MiB limit.
async fn FilePipeline::push(
  self : FilePipeline,
  path : String,
  snapshot : @input.Snapshot,
  kept_full : Bool,
) -> Unit {
  let bytes = snapshot.disk_bytes - snapshot.bom_bytes
  if self.compress &&
    (bytes > 8 * 1024 * 1024 || bytes > 16 * 1024 * 1024 - self.pending_bytes) {
    self.flush()
  }
  let file = {
    path,
    snapshot,
    kept_full,
    original_tokens: self.counter.count(snapshot.text),
  }
  if !self.compress || bytes > 8 * 1024 * 1024 {
    self.record_serial(file)
    return
  }
  self.pending.push(file)
  self.pending_bytes += bytes
  if self.pending.length() == 4 {
    self.start_pending()
  }
}

///|
async fn FilePipeline::finish_active(self : FilePipeline) -> Unit {
  guard self.active is Some(batch) else { return }
  let results = batch.ticket.finish()
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
      file.original_tokens,
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
  self.active = None
}

///|
async fn FilePipeline::start_pending(self : FilePipeline) -> Unit {
  if self.pending.is_empty() {
    return
  }
  // A pool admits only one active C batch. Finish it in source order after
  // the caller has already read, screened and counted the lookahead window.
  self.finish_active()
  let sources : Array[@compression.Source] = []
  for file in self.pending {
    if !file.kept_full {
      sources.push({ path: file.path, text: file.snapshot.text, })
    }
  }
  if !sources.is_empty() && !self.planner_attempted {
    self.planner_attempted = true
    self.planner = Some(@compression.Planner::new(workers=3)) catch {
      @compression.PlannerError::Unavailable => None
      err => raise err
    }
  }
  if sources.is_empty() || self.planner is None {
    for file in self.pending {
      self.record_serial(file)
    }
  } else if self.planner is Some(planner) {
    let ticket = planner.submit(sources) catch {
      // Submission stages every C-owned source before starting any worker.
      @compression.PlannerError::Unavailable => {
        self.planner = None
        planner.close()
        for file in self.pending {
          self.record_serial(file)
        }
        self.pending.clear()
        self.pending_bytes = 0
        return
      }
      err => raise err
    }
    self.active = Some({ ticket, files: self.pending, })
  }
  self.pending = []
  self.pending_bytes = 0
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
  // A cancelled/error path releases the pool before dropping queued snapshots.
  self.active = None
  self.pending.clear()
  self.pending_bytes = 0
}
