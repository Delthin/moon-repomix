///|
priv struct VolumeMetadata {
  document : Document
  active : Bool
  source : Json
  compression : Map[String, Json]
  diffs : Map[Int32, Json]
  commits : Map[Int32, Json]
  has_git : Bool
}

///|
/// Bind Git records by kind/order, never by title or the files in a volume.
fn volume_metadata(document : Document) -> VolumeMetadata raise {
  let compression : Map[String, Json] = Map([])
  let diffs : Map[Int32, Json] = Map([])
  let commits : Map[Int32, Json] = Map([])
  if document.metadata == Json::null() {
    return {
      document,
      active: false,
      source: Json::null(),
      compression,
      diffs,
      commits,
      has_git: false,
    }
  }
  guard document.metadata is Object(fields) else { raise ConfigurationError }
  let source = fields.get("source").unwrap_or(Json::null())
  let records = match fields.get("compression") {
    None => []
    Some(Array(records)) => records
    _ => raise ConfigurationError
  }
  let paths : Set[String] = Set([])
  for file in document.files {
    paths.add(file.path)
  }
  for record in records {
    guard record is { "path": String(path), .. } else {
      raise ConfigurationError
    }
    if !paths.contains(path) || compression.contains(path) {
      raise ConfigurationError
    }
    compression[path] = record
  }
  let (diff_records, commit_records, has_git) = match fields.get("git") {
    None | Some(Null) => ([], [], false)
    Some({ "diffs": Array(diff_records), "commits": Array(commit_records), .. }) =>
      (diff_records, commit_records, true)
    _ => raise ConfigurationError
  }
  let mut next_diff = 0
  let mut next_commit = 0
  for index, section in document.sections {
    match section.kind {
      "git_diff" => {
        if next_diff >= diff_records.length() {
          raise ConfigurationError
        }
        diffs[index] = diff_records[next_diff]
        next_diff += 1
      }
      "git_log" => {
        if next_commit >= commit_records.length() {
          raise ConfigurationError
        }
        commits[index] = commit_records[next_commit]
        next_commit += 1
      }
      _ => ()
    }
  }
  if next_diff != diff_records.length() ||
    next_commit != commit_records.length() {
    raise ConfigurationError
  }
  { document, active: true, source, compression, diffs, commits, has_git, }
}

///|
fn VolumeMetadata::project(
  self : VolumeMetadata,
  file_indices : Array[Int32],
  section_indices : Array[Int32],
) -> Json raise {
  if !self.active {
    return Json::null()
  }
  let compression : Array[Json] = []
  let diffs : Array[Json] = []
  let commits : Array[Json] = []
  for index in file_indices {
    if index < 0 || index >= self.document.files.length() {
      raise ConfigurationError
    }
    let path = self.document.files[index].path
    if self.compression.get(path) is Some(record) {
      compression.push(record)
    }
  }
  for index in section_indices {
    if index < 0 || index >= self.document.sections.length() {
      raise ConfigurationError
    }
    if self.diffs.get(index) is Some(record) {
      diffs.push(record)
    }
    if self.commits.get(index) is Some(record) {
      commits.push(record)
    }
  }
  {
    "source": self.source,
    "compression": compression,
    "git": if self.has_git {
      { "diffs": diffs, "commits": commits }
    } else {
      Json::null()
    },
  }
}
