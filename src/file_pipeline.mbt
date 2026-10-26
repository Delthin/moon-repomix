///|
priv struct PendingFile {
  path : String
  snapshot : @input.Snapshot
  kept_full : Bool
}

///|
priv struct FilePipeline {
  runtime : Runtime
  compress : Bool
  accepted : Array[@document.File]
  files : Array[FileStats]
  transforms : Array[Json]
  pending : Array[PendingFile]
  mut pending_bytes : Int32
  mut planner_attempted : Bool
  mut planner : @compression.Planner?
}

///|
fn FilePipeline::new(
  runtime : Runtime,
  compress : Bool,
  accepted : Array[@document.File],
  files : Array[FileStats],
  transforms : Array[Json],
) -> FilePipeline {
  {
    runtime,
    compress,
    accepted,
    files,
    transforms,
    pending: [],
    pending_bytes: 0,
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
  let original_tokens = self.runtime.encoder.count(file.snapshot.text)
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
    original_tokens,
    outcome,
    self.runtime,
    self.accepted,
    self.files,
    self.transforms,
  )
}

///|
// Sources are admitted only after ordered metered reads and complete screening.
// Larger individual sources retain the serial compressor's resource fallback.
async fn FilePipeline::push(
  self : FilePipeline,
  path : String,
  snapshot : @input.Snapshot,
  kept_full : Bool,
) -> Unit {
  let file = { path, snapshot, kept_full, }
  if !self.compress {
    self.record_serial(file)
    return
  }
  let bytes = snapshot.disk_bytes - snapshot.bom_bytes
  if bytes > 8 * 1024 * 1024 {
    self.flush()
    self.record_serial(file)
    return
  }
  if self.pending.length() == 4 || bytes > 16 * 1024 * 1024 - self.pending_bytes {
    self.flush()
  }
  self.pending.push(file)
  self.pending_bytes += bytes
  if self.pending.length() == 4 {
    self.flush()
  }
}

///|
async fn FilePipeline::flush(self : FilePipeline) -> Unit {
  if self.pending.is_empty() {
    return
  }
  let sources : Array[@compression.Source] = []
  for file in self.pending {
    if !file.kept_full {
      sources.push({ path: file.path, text: file.snapshot.text, })
    }
  }
  if !sources.is_empty() && !self.planner_attempted {
    self.planner_attempted = true
    // Three AST workers plus the caller's single-threaded exact token counter.
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
      // No worker starts until submission has staged every C-owned source.
      // Release the unavailable pool before using the exact serial path.
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
    // submit has started the independent C workers. Exact original counts can
    // run on the caller while their parse/walk work is in flight.
    let originals : Array[Int32] = []
    for file in self.pending {
      originals.push(self.runtime.encoder.count(file.snapshot.text))
    }
    let results = ticket.finish()
    if results.length() != sources.length() {
      raise @compression.PlannerError::Unavailable
    }
    let mut result_index = 0
    for i in 0..<self.pending.length() {
      let file = self.pending[i]
      let outcome = if file.kept_full {
        kept_full_outcome(file.snapshot.text)
      } else {
        let result = results[result_index]
        result_index += 1
        result
      }
      record_file_result(
        file.path,
        file.snapshot,
        originals[i],
        Some(outcome),
        self.runtime,
        self.accepted,
        self.files,
        self.transforms,
      )
    }
  }
  self.pending.clear()
  self.pending_bytes = 0
}

///|
async fn FilePipeline::close(self : FilePipeline) -> Unit {
  if self.planner is Some(planner) {
    self.planner = None
    planner.close()
  }
  self.pending.clear()
  self.pending_bytes = 0
}
