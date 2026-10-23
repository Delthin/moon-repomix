///|
pub using @config {type Options, type Style, type PathStyle}

///|
pub using @security {type Finding}

///|
pub using @selection {type Skipped}

///|
pub using @document {type Document, type Section}

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
  ContextTextError(String)
  ContextSecurityFinding(String)
  SelectionError
  ScanError
  ResourceError
  GitError
  RemoteError
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
/// Body counts precede presentation line prefixes and format escaping.
/// PackResult.tokens counts the complete rendered document instead.
pub(all) struct FileStats {
  path : String
  disk_bytes : Int32
  tokens : Int32
  original_tokens : Int32
}

///|
/// Excluded files retain only metadata; their contents are absent.
pub struct PackResult {
  document : Document
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
/// Validated options for one directory, with the selected format and scanning enabled.
///
/// Use `options("/absolute/project", style=Json)` to select JSON and its default filename.
pub fn options(
  directory : String,
  style~ : Style = Xml,
  compress~ : Bool = false,
  keep_full_patterns~ : Array[String] = [],
  header_text~ : String = "",
  instruction_file_path~ : String? = None,
  full_metadata~ : Bool = false,
  file_summary~ : Bool = true,
  directory_structure~ : Bool = true,
  include_files~ : Bool = true,
  git_sections~ : Bool = true,
  metadata~ : Bool = true,
  show_line_numbers~ : Bool = false,
  output_file_path_style~ : PathStyle = TargetRelative,
  file_paths~ : Array[String]? = None,
  include_diffs~ : Bool = false,
  include_logs~ : Bool = false,
  include_logs_count~ : Int32 = 50,
  remote~ : String? = None,
  remote_branch~ : String? = None,
) -> Options raise {
  let cli = @config.parse_cli([directory])
  cli.patch.style = Some(style)
  cli.patch.compress = Some(compress)
  cli.patch.keep_full_patterns = keep_full_patterns.copy()
  cli.patch.header_text = Some(header_text)
  cli.patch.instruction_file_path = instruction_file_path
  cli.patch.full_metadata = Some(full_metadata)
  cli.patch.file_summary = Some(file_summary)
  cli.patch.directory_structure = Some(directory_structure)
  cli.patch.include_files = Some(include_files)
  cli.patch.git_sections = Some(git_sections)
  cli.patch.metadata = Some(metadata)
  cli.patch.show_line_numbers = Some(show_line_numbers)
  cli.patch.output_file_path_style = Some(output_file_path_style)
  cli.patch.include_diffs = Some(include_diffs)
  cli.patch.include_logs = Some(include_logs)
  cli.patch.include_logs_count = Some(include_logs_count)
  cli.patch.remote = remote
  cli.patch.remote_branch = remote_branch
  let resolved = @config.resolve(cli, None)
  {
    ..resolved,
    file_paths: match file_paths {
      None => None
      Some(paths) => Some(paths.copy())
    },
  }
}
