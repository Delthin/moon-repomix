///|
pub using @config {type Options, type Style}

///|
pub using @security {type Finding}

///|
pub using @selection {type Skipped}

///|
/// Validated resources shared by sequential pack operations.
pub struct Runtime {
  encoder : @metrics.Encoder
}

///|
pub async fn Runtime::load(tokenizer_path : String) -> Runtime {
  let encoder = @metrics.Encoder::load(tokenizer_path) catch {
    err => {
      if @async.is_cancellation_error(err) {
        raise err
      }
      raise ResourceError
    }
  }
  { encoder, }
}

///|
pub(all) suberror PackError {
  ConfigurationError
  SelectionError
  ScanError
  ResourceError
}

///|
pub(all) enum SecurityStatus {
  Passed
  Excluded
  Disabled
}

///|
pub(all) enum BudgetStatus {
  NotSet
  Within(Int32)
  Exceeded(Int32)
}

///|
pub(all) struct FileStats {
  path : String
  disk_bytes : Int32
  tokens : Int32
}

///|
/// Excluded files retain only metadata; their contents are absent.
pub struct PackResult {
  text : String
  bytes : Int32
  tokens : Int32
  files : Array[FileStats]
  skipped : Array[Skipped]
  findings : Array[Finding]
  security : SecurityStatus
  budget : BudgetStatus
}

///|
/// Default validated options for one directory, with XML and scanning enabled.
pub fn options(directory : String) -> Options raise {
  @config.resolve(@config.parse_cli([directory]), None)
}
