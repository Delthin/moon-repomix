///|
pub(all) enum Style {
  Xml
  Markdown
  Json
  Plain
} derive(Eq, Debug)

///|
/// CLI reporting only; thresholds use the sum of accepted file content tokens.
pub(all) enum TokenCountTree {
  Disabled
  Enabled(Int32)
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
  mut compress : Bool?
  mut full_metadata : Bool?
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
  mut tokenizer_path : String?
} derive(Debug)

///|
pub fn Patch::empty() -> Patch {
  {
    output: None,
    style: None,
    compress: None,
    full_metadata: None,
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
  compress : Bool
  full_metadata : Bool
  include_diffs : Bool
  include_logs : Bool
  include_logs_count : Int32
  remote : String?
  remote_branch : String?
  max_git_bytes : Int32
  include_patterns : Array[String]
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
pub extend TokenCountTree with Eq::{equal, not_equal}

///|
pub extend TokenCountTree with Debug::{to_repr}

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with Debug::{to_repr}

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
    pattern.contains("{") ||
    pattern.contains("}") {
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
  if patch.encoding is Some(value) && value != "o200k_base" {
    raise InvalidValue("tokenCount.encoding")
  }
  if patch.token_budget is Some(value) && value <= 0 {
    raise InvalidValue("output.tokenBudget")
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
  if patch.output is Some(value) {
    validate_path(value, "output.filePath")
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
  // Only an explicitly supplied CLI --output conflicts with --stdout.
  if cli.stdout && cli.patch.output is Some(_) {
    raise Conflict("output/stdout")
  }
  let patch = cli.patch
  let style = patch.style.unwrap_or(file.style.unwrap_or(Xml))
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
    output: patch.output.unwrap_or(
      file.output.unwrap_or(
        match style {
          Xml => "repomix-output.xml"
          Markdown => "repomix-output.md"
          Json => "repomix-output.json"
          Plain => "repomix-output.txt"
        },
      ),
    ),
    stdout: cli.stdout,
    style,
    compress: patch.compress.unwrap_or(file.compress.unwrap_or(false)),
    full_metadata: patch.full_metadata.unwrap_or(
      file.full_metadata.unwrap_or(false),
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
    token_budget: match patch.token_budget {
      Some(_) as value => value
      None => file.token_budget
    },
    top_files_length: patch.top_files_length.unwrap_or(
      file.top_files_length.unwrap_or(5),
    ),
    token_count_tree: patch.token_count_tree.unwrap_or(
      file.token_count_tree.unwrap_or(Disabled),
    ),
    max_file_size: patch.max_file_size.unwrap_or(
      file.max_file_size.unwrap_or(52428800),
    ),
    tokenizer_path: match patch.tokenizer_path {
      Some(_) as value => value
      None => file.tokenizer_path
    },
    quiet: cli.quiet,
    verbose: cli.verbose,
  }
}
