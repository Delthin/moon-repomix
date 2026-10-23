///|
pub(all) enum Style {
  Xml
  Markdown
  Json
  Plain
} derive(Eq, Debug)

///|
pub(all) enum PathStyle {
  TargetRelative
  CwdRelative
  Absolute
} derive(Eq, Debug)

///|
pub(all) enum SplitOutput {
  Disabled
  Enabled(Int32)
} derive(Eq, Debug)

///|
pub extend SplitOutput with Eq::{equal, not_equal}

///|
pub extend SplitOutput with Debug::{to_repr}

///|
fn parse_path_style(value : String) -> PathStyle raise ConfigError {
  match value {
    "target-relative" => TargetRelative
    "cwd-relative" => CwdRelative
    "absolute" => Absolute
    _ => raise InvalidValue("output.filePathStyle")
  }
}

///|
/// CLI reporting only; thresholds use the sum of accepted file content tokens.
pub(all) enum TokenCountTree {
  Disabled
  Enabled(Int32)
} derive(Eq, Debug)

///|
/// Explicit CLI file-list input. Configuration files never enable stdin reads.
pub(all) enum StdinMode {
  Off
  Lines
  Nul
} derive(Eq, Debug)

///|
pub(all) enum Action {
  Pack
  Init
  Help
  Version
} derive(Eq, Debug)

///|
/// Absent scalars stay None; lists are additive, not replacement values.
pub(all) struct Patch {
  mut output : String?
  mut style : Style?
  mut split_output : SplitOutput?
  mut compress : Bool?
  mut keep_full_patterns : Array[String]
  mut header_text : String?
  mut instruction_file_path : String?
  mut full_metadata : Bool?
  mut file_summary : Bool?
  mut directory_structure : Bool?
  mut include_files : Bool?
  mut git_sections : Bool?
  mut metadata : Bool?
  mut show_line_numbers : Bool?
  mut output_file_path_style : PathStyle?
  mut include_diffs : Bool?
  mut include_logs : Bool?
  mut include_logs_count : Int32?
  mut remote : String?
  mut remote_branch : String?
  mut max_git_bytes : Int32?
  mut include_patterns : Array[String]
  mut ignore : Array[String]
  mut use_gitignore : Bool?
  mut use_dot_ignore : Bool?
  mut use_default_patterns : Bool?
  mut security_check : Bool?
  mut encoding : String?
  mut token_budget : Int32?
  mut top_files_length : Int32?
  mut token_count_tree : TokenCountTree?
  mut max_file_size : Int32?
  mut max_files : Int32?
  mut max_total_size : Int64?
  mut tokenizer_path : String?
} derive(Debug)

///|
pub fn Patch::empty() -> Patch {
  {
    output: None,
    style: None,
    split_output: None,
    compress: None,
    keep_full_patterns: [],
    header_text: None,
    instruction_file_path: None,
    full_metadata: None,
    file_summary: None,
    directory_structure: None,
    include_files: None,
    git_sections: None,
    metadata: None,
    show_line_numbers: None,
    output_file_path_style: None,
    include_diffs: None,
    include_logs: None,
    include_logs_count: None,
    remote: None,
    remote_branch: None,
    max_git_bytes: None,
    include_patterns: [],
    ignore: [],
    use_gitignore: None,
    use_dot_ignore: None,
    use_default_patterns: None,
    security_check: None,
    encoding: None,
    token_budget: None,
    top_files_length: None,
    token_count_tree: None,
    max_file_size: None,
    max_files: None,
    max_total_size: None,
    tokenizer_path: None,
  }
}

///|
/// All paths are unmodified user paths; this package performs no I/O.
pub(all) struct Cli {
  directory : String
  config_path : String?
  action : Action
  stdout : Bool
  stdin_mode : StdinMode
  report_json : Bool
  mcp : Bool
  mcp_max_tokens : Int32
  mcp_max_output_bytes : Int32
  mcp_max_volumes : Int32
  quiet : Bool
  verbose : Bool
  patch : Patch
} derive(Debug)

///|
pub(all) struct Options {
  directory : String
  output : String
  stdout : Bool
  style : Style
  split_output : SplitOutput
  compress : Bool
  keep_full_patterns : Array[String]
  header_text : String
  instruction_file_path : String?
  full_metadata : Bool
  file_summary : Bool
  directory_structure : Bool
  include_files : Bool
  git_sections : Bool
  metadata : Bool
  show_line_numbers : Bool
  output_file_path_style : PathStyle
  include_diffs : Bool
  include_logs : Bool
  include_logs_count : Int32
  remote : String?
  remote_branch : String?
  max_git_bytes : Int32
  include_patterns : Array[String]
  file_paths : Array[String]?
  ignore : Array[String]
  use_gitignore : Bool
  use_dot_ignore : Bool
  use_default_patterns : Bool
  security_check : Bool
  encoding : String
  token_budget : Int32?
  top_files_length : Int32
  token_count_tree : TokenCountTree
  max_file_size : Int32
  max_files : Int32
  max_total_size : Int64
  tokenizer_path : String?
  quiet : Bool
  verbose : Bool
} derive(Debug)

///|
/// Error payloads contain field/option names, never source JSON or values.
pub(all) suberror ConfigError {
  InvalidJson
  UnknownField(String)
  InvalidValue(String)
  UnknownOption(String)
  MissingValue(String)
  Conflict(String)
  MultipleDirectories
} derive(Eq, Debug)

///|
pub extend Style with Eq::{equal, not_equal}

///|
pub extend Style with Debug::{to_repr}

///|
pub extend PathStyle with Eq::{equal, not_equal}

///|
pub extend PathStyle with Debug::{to_repr}

///|
pub extend TokenCountTree with Eq::{equal, not_equal}

///|
pub extend TokenCountTree with Debug::{to_repr}

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with Debug::{to_repr}

///|
pub extend StdinMode with Eq::{equal, not_equal}

///|
pub extend StdinMode with Debug::{to_repr}

///|
pub extend Patch with Debug::{to_repr}

///|
pub extend Cli with Debug::{to_repr}

///|
pub extend Options with Debug::{to_repr}

///|
pub extend ConfigError with Eq::{equal, not_equal}

///|
pub extend ConfigError with Debug::{to_repr}

///|
fn parse_style(value : String) -> Style raise ConfigError {
  match value {
    "xml" => Xml
    "markdown" => Markdown
    "json" => Json
    "plain" => Plain
    _ => raise InvalidValue("output.style")
  }
}

///|
fn validate_pattern(pattern : String) -> Unit raise ConfigError {
  if pattern.is_empty() ||
    pattern.has_prefix("!") ||
    pattern.has_prefix("/") ||
    pattern.contains("\\") ||
    pattern.contains(":") ||
    pattern.contains("\u0000") {
    raise InvalidValue("glob")
  }
  for part in pattern.split("/") {
    if part == ".." {
      raise InvalidValue("glob")
    }
  }
}

///|
fn validate_patch(patch : Patch) -> Unit raise ConfigError {
  for p in patch.include_patterns {
    validate_pattern(p)
  }
  for p in patch.ignore {
    validate_pattern(p)
  }
  for p in patch.keep_full_patterns {
    validate_pattern(p)
  }
  if patch.encoding is Some(value) && value != "o200k_base" {
    raise InvalidValue("tokenCount.encoding")
  }
  if patch.token_budget is Some(value) && value <= 0 {
    raise InvalidValue("output.tokenBudget")
  }
  if patch.split_output is Some(SplitOutput::Enabled(value)) && value <= 0 {
    raise InvalidValue("output.splitOutput")
  }
  if patch.top_files_length is Some(value) && value < 0 {
    raise InvalidValue("output.topFilesLength")
  }
  if patch.token_count_tree is Some(Enabled(value)) && value < 0 {
    raise InvalidValue("output.tokenCountTree")
  }
  if patch.max_file_size is Some(value) && value <= 0 {
    raise InvalidValue("input.maxFileSize")
  }
  if patch.max_files is Some(value) && value < 0 {
    raise InvalidValue("input.maxFiles")
  }
  if patch.max_total_size is Some(value) &&
    (value < 0 || value > 9007199254740991L) {
    raise InvalidValue("input.maxTotalSize")
  }
  if patch.output is Some(value) {
    validate_path(value, "output.filePath")
  }
  if patch.instruction_file_path is Some(value) && !value.is_empty() {
    validate_path(value, "output.instructionFilePath")
  }
  if patch.tokenizer_path is Some(value) {
    validate_path(value, "tokenizerPath")
  }
  if patch.include_logs_count is Some(value) && (value <= 0 || value > 10000) {
    raise InvalidValue("output.git.includeLogsCount")
  }
  if patch.max_git_bytes is Some(value) && value <= 0 {
    raise InvalidValue("input.maxGitBytes")
  }
  if patch.remote is Some(value) {
    validate_path(value, "remote.url")
  }
  if patch.remote_branch is Some(value) {
    validate_path(value, "remote.branch")
  }
}

///|
fn validate_path(value : String, field : String) -> Unit raise ConfigError {
  if value.is_empty() || value.contains("\u0000") {
    raise InvalidValue(field)
  }
}

///|
fn append_unique(
  first : Array[String],
  second : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  let seen : Map[String, Unit] = Map([])
  for items in [first, second] {
    for item in items {
      if !seen.contains(item) {
        seen[item] = ()
        result.push(item)
      }
    }
  }
  result
}

///|
/// Defaults -> selected JSON -> explicit CLI. No paths are resolved here.
pub fn resolve(cli : Cli, json : Patch?) -> Options raise ConfigError {
  let file = json.unwrap_or(Patch::empty())
  validate_patch(file)
  validate_patch(cli.patch)
  validate_path(cli.directory, "directory")
  if cli.config_path is Some(path) {
    validate_path(path, "config")
  }
  if cli.quiet && cli.verbose {
    raise Conflict("quiet/verbose")
  }
  // '-' agrees with --stdout; an explicit regular filename conflicts.
  if cli.stdout && cli.patch.output is Some(path) && path != "-" {
    raise Conflict("output/stdout")
  }
  let patch = cli.patch
  let style = patch.style.unwrap_or(file.style.unwrap_or(Xml))
  let split_output = patch.split_output.unwrap_or(
    file.split_output.unwrap_or(SplitOutput::Disabled),
  )
  let default_output = if split_output is SplitOutput::Enabled(_) {
    "moon-repomix-output"
  } else {
    match style {
      Xml => "repomix-output.xml"
      Markdown => "repomix-output.md"
      Json => "repomix-output.json"
      Plain => "repomix-output.txt"
    }
  }
  let output = patch.output.unwrap_or(file.output.unwrap_or(default_output))
  let token_budget = match patch.token_budget {
    Some(_) as value => value
    None => file.token_budget
  }
  if split_output is SplitOutput::Enabled(_) &&
    (cli.stdout || output == "-" || token_budget is Some(_)) {
    raise Conflict("splitOutput/stdout/tokenBudget")
  }
  let instruction_file_path = match patch.instruction_file_path {
    Some(_) as explicit => explicit
    None => file.instruction_file_path
  }
  let remote = match patch.remote {
    Some(_) as value => value
    None => file.remote
  }
  let remote_branch = match patch.remote_branch {
    Some(_) as value => value
    None => file.remote_branch
  }
  if remote_branch is Some(_) && remote is None {
    raise Conflict("remote.branch/remote.url")
  }
  if remote is Some(_) && cli.directory != "." {
    raise Conflict("remote/directory")
  }
  {
    directory: cli.directory,
    output,
    stdout: cli.stdout || output == "-",
    style,
    split_output,
    compress: patch.compress.unwrap_or(file.compress.unwrap_or(false)),
    keep_full_patterns: append_unique(
      file.keep_full_patterns,
      patch.keep_full_patterns,
    ),
    header_text: patch.header_text.unwrap_or(file.header_text.unwrap_or("")),
    instruction_file_path: match instruction_file_path {
      Some("") => None
      other => other
    },
    full_metadata: patch.full_metadata.unwrap_or(
      file.full_metadata.unwrap_or(false),
    ),
    file_summary: patch.file_summary.unwrap_or(
      file.file_summary.unwrap_or(true),
    ),
    directory_structure: patch.directory_structure.unwrap_or(
      file.directory_structure.unwrap_or(true),
    ),
    include_files: patch.include_files.unwrap_or(
      file.include_files.unwrap_or(true),
    ),
    git_sections: patch.git_sections.unwrap_or(
      file.git_sections.unwrap_or(true),
    ),
    metadata: patch.metadata.unwrap_or(file.metadata.unwrap_or(true)),
    show_line_numbers: patch.show_line_numbers.unwrap_or(
      file.show_line_numbers.unwrap_or(false),
    ),
    output_file_path_style: patch.output_file_path_style.unwrap_or(
      file.output_file_path_style.unwrap_or(TargetRelative),
    ),
    include_diffs: patch.include_diffs.unwrap_or(
      file.include_diffs.unwrap_or(false),
    ),
    include_logs: patch.include_logs.unwrap_or(
      file.include_logs.unwrap_or(false),
    ),
    include_logs_count: patch.include_logs_count.unwrap_or(
      file.include_logs_count.unwrap_or(50),
    ),
    remote,
    remote_branch,
    max_git_bytes: patch.max_git_bytes.unwrap_or(
      file.max_git_bytes.unwrap_or(8388608),
    ),
    include_patterns: append_unique(
      file.include_patterns,
      patch.include_patterns,
    ),
    file_paths: None,
    ignore: append_unique(file.ignore, patch.ignore),
    use_gitignore: patch.use_gitignore.unwrap_or(
      file.use_gitignore.unwrap_or(true),
    ),
    use_dot_ignore: patch.use_dot_ignore.unwrap_or(
      file.use_dot_ignore.unwrap_or(true),
    ),
    use_default_patterns: patch.use_default_patterns.unwrap_or(
      file.use_default_patterns.unwrap_or(true),
    ),
    security_check: patch.security_check.unwrap_or(
      file.security_check.unwrap_or(true),
    ),
    encoding: patch.encoding.unwrap_or(file.encoding.unwrap_or("o200k_base")),
    token_budget,
    top_files_length: patch.top_files_length.unwrap_or(
      file.top_files_length.unwrap_or(5),
    ),
    token_count_tree: patch.token_count_tree.unwrap_or(
      file.token_count_tree.unwrap_or(Disabled),
    ),
    max_file_size: patch.max_file_size.unwrap_or(
      file.max_file_size.unwrap_or(52428800),
    ),
    max_files: patch.max_files.unwrap_or(file.max_files.unwrap_or(20000)),
    max_total_size: patch.max_total_size.unwrap_or(
      file.max_total_size.unwrap_or(209715200L),
    ),
    tokenizer_path: match patch.tokenizer_path {
      Some(_) as value => value
      None => file.tokenizer_path
    },
    quiet: cli.quiet,
    verbose: cli.verbose,
  }
}
