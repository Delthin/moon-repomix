///|
/// Positive include filters and independent exclusion layers. Output must be absolute.
pub(all) struct SelectionOptions {
  include_patterns : Array[String]
  ignore : Array[String]
  use_gitignore : Bool
  use_dot_ignore : Bool
  use_default_patterns : Bool
  output : String?
}

///|
/// Enable project ignore files and built-in exclusions, with no include restriction.
pub fn SelectionOptions::default() -> SelectionOptions {
  {
    include_patterns: [],
    ignore: [],
    use_gitignore: true,
    use_dot_ignore: true,
    use_default_patterns: true,
    output: None,
  }
}

///|
/// An ordinary file, not yet opened or read. Relative uses '/' and original Unicode.
pub(all) struct Candidate {
  path : String
  relative : String
}

///|
/// Path is root-relative. Reasons are documented in docs/file-selection.md.
pub(all) struct Skipped {
  path : String
  reason : String
}

///|
pub(all) struct Selection {
  root : String
  files : Array[Candidate]
  skipped : Array[Skipped]
}

///|
/// Safe rule provenance: no pattern text; source is root-relative or None.
/// index is zero-based in the compiled (brace-expanded) matcher list.
pub(all) struct RuleOrigin {
  kind : String
  source : String?
  line : Int32?
  index : Int32?
}

///|
/// Candidate means structurally eligible, not yet read or security-scanned.
pub(all) struct PathDecision {
  path : String
  eligible : Bool
  reason : String
  origin : RuleOrigin?
}

///|
/// The selection and decisions describe the same exact query, without reselection.
pub(all) struct SelectionExplanation {
  selection : Selection
  decisions : Array[PathDecision]
}

///|
/// Validation failures. Filesystem failures and cancellation propagate unchanged.
pub(all) suberror SelectionError {
  InvalidRoot(String)
  FileLimitExceeded(limit~ : Int32)
  InvalidPattern(
    source~ : String,
    line~ : Int32,
    pattern~ : String,
    detail~ : String
  )
  InvalidRuleFile(String)
  InvalidGitMetadata(String)
  InvalidOutput(String)
}
