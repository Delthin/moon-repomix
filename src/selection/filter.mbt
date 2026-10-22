///|
#cfg(platform="windows")
fn git_path_spelling(path : String) -> Bool {
  !path.contains("\\") && !path.contains(":")
}

///|
#cfg(not(platform="windows"))
fn git_path_spelling(_path : String) -> Bool {
  true
}

///|
/// Current working-tree rules for Git paths, including deleted files.
struct PathFilter {
  root : String
  options : SelectionOptions
  includes : Array[Pattern]
  custom : Array[Pattern]
  defaults : Array[Pattern]
  inherited : Array[Rule]
  blocked : Rule?
  output : String?
  exact : Map[String, Bool]?
  cache : Map[String, Array[Rule]]
}

///|
async fn make_path_filter(
  root : String,
  options : SelectionOptions,
  paths : Array[String]?,
) -> PathFilter {
  let includes = custom_patterns(options.include_patterns, "include")
  let custom = custom_patterns(options.ignore, "ignore")
  let defaults = default_patterns(options.use_default_patterns)
  let output = match options.output {
    None => None
    Some(path) => {
      if !absolute(separators(path)) {
        raise SelectionError::InvalidOutput(path)
      }
      Some(normalize(output_identity(separators(path))))
    }
  }
  let (inherited, blocked) = inherited_rules(root, options)
  {
    root,
    options,
    includes,
    custom,
    defaults,
    inherited,
    blocked,
    output,
    exact: paths.map(paths => Map::from_array(paths.map(path => (path, true)))),
    cache: Map([]),
  }
}

///|
/// The root is the canonical root returned by `select`.
/// Some([]) selects no paths; explicit entries are literal root-relative files.
pub async fn path_filter(
  root : String,
  options : SelectionOptions,
  file_paths~ : Array[String]? = None,
) -> PathFilter {
  let paths = exact_paths(file_paths)
  if !absolute(root) || optional_kind(root) != Some(Directory) {
    raise SelectionError::InvalidRoot(root)
  }
  make_path_filter(root, options, paths)
}

///|
// Shared decision for exact candidate discovery and Git filtering. Only the
// latter allows missing paths (deletions). Ancestors are checked before loading
// rules beneath them, and no candidate body or directory listing is opened.
async fn PathFilter::reason(
  self : PathFilter,
  relative : String,
  require_file : Bool,
) -> String? {
  if !relative_file_path(relative) || !git_path_spelling(relative) {
    return Some("InvalidPath")
  }
  if self.exact is Some(paths) && !paths.contains(relative) {
    return Some("NotListed")
  }
  if self.blocked is Some(rule) {
    return Some("IgnoredDirectory:\{rule.source}:\{rule.line}")
  }
  let parts = relative.split("/").map(p => p.to_owned()).collect()
  let mut directory = self.root
  let mut inherited = self.inherited
  let mut partial = ""
  for i in 0..<parts.length() {
    let rules = match self.cache.get(directory) {
      Some(rules) => rules
      None => {
        let rules = local_rules(directory, inherited, self.options)
        self.cache[directory] = rules
        rules
      }
    }
    let part = parts[i]
    partial = if partial == "" { part } else { partial + "/" + part }
    let path = join(directory, part)
    let is_dir = i < parts.length() - 1
    match optional_kind(path) {
      Some(SymLink) => return Some("Symlink")
      Some(Directory) if !is_dir => return Some("Directory")
      Some(Regular) if is_dir => return Some("NotDirectory")
      Some(kind) if kind != Regular && kind != Directory =>
        return Some("UnsupportedFileType")
      None if require_file => return Some("MissingFile")
      _ => ()
    }
    if self.output is Some(output) && normalize(path) == output {
      return Some("OutputFile")
    }
    let ignored = if is_dir { "IgnoredDirectory" } else { "Ignored" }
    if self.defaults.any(p => p.matches(partial, is_dir)) {
      return Some("\{ignored}:default")
    }
    if self.custom.any(p => p.matches(partial, is_dir)) {
      return Some("\{ignored}:custom")
    }
    if ignored_by(rules, path, is_dir) is Some(rule) {
      return Some("\{ignored}:\{rule.source}:\{rule.line}")
    }
    directory = path
    inherited = rules
  }
  if included(self.includes, relative) {
    None
  } else {
    Some("NotIncluded")
  }
}

///|
/// Apply include/ignore, ancestor pruning and no-follow rules without opening a file.
/// Missing paths are valid because Git diffs and history can describe deletions.
pub async fn PathFilter::allows(self : PathFilter, relative : String) -> Bool {
  self.reason(relative, false) is None
}
