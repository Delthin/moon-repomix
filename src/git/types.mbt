///|
pub(all) struct Diff {
  kind : String
  paths : Array[String]
  text : String
}

///|
pub(all) struct Commit {
  id : String
  date : String
  message : String
  files : Array[String]
}

///|
pub(all) struct Snapshot {
  repository_root : String
  revision : String?
  diffs : Array[Diff]
  commits : Array[Commit]
}

///|
pub(all) struct Checkout {
  directory : String
  url : String
  revision : String
}

///|
/// Errors deliberately omit child stderr, URLs, paths and source contents.
pub(all) suberror GitError {
  InvalidInput(String)
  NotRepository
  CommandFailed(String, Int32)
  InvalidOutput
  OutputLimit
}
