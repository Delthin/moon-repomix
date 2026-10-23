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
  names : Map[String, Map[String, Bool]]
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
    names: Map([]),
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
// rules beneath them. Exact lists also check on-disk spelling using cached names
// of visited parents; pruned directories are never listed or entered.
async fn PathFilter::decision(
  self : PathFilter,
  relative : String,
  require_file : Bool,
) -> Exclusion? {
  if !relative_file_path(relative) || !git_path_spelling(relative) {
    return Some(Fixed("InvalidPath"))
  }
  if self.exact is Some(paths) && !paths.contains(relative) {
    return Some(Fixed("NotListed"))
  }
  if self.blocked is Some(rule) {
    return Some(RuleFile(rule, true))
  }
  let parts = relative.split("/").map(p => p.to_owned()).collect()
  let mut directory = self.root
  let mut inherited = self.inherited
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
    let path = join(directory, part)
    let is_dir = i < parts.length() - 1
    let kind = optional_kind(path)
    if type_exclusion(kind) is Some(exclusion) {
      return Some(exclusion)
    }
    if kind is None && require_file {
      return Some(Fixed("MissingFile"))
    }
    if (require_file || self.exact is Some(_)) && kind is Some(_) {
      // stat can accept case-folded, normalization or short-name aliases. Only
      // ordinary existing entries reach here; compare their parent's raw names
      // before entering this component or applying string-based exclusions.
      let names = match self.names.get(directory) {
        Some(names) => names
        None => {
          let names = Map::from_array(
            @fs.readdir(directory, include_hidden=true, sort=false).map(name => {
              (name, true)
            }),
          )
          self.names[directory] = names
          names
        }
      }
      if !names.contains(part) {
        return Some(Fixed("NonLiteralPath"))
      }
    }
    match kind {
      Some(Directory) if !is_dir => return Some(Fixed("Directory"))
      Some(Regular) if is_dir => return Some(Fixed("NotDirectory"))
      _ => ()
    }
    if self.exclusion(path, normalize(path), parts[:i + 1], is_dir, rules)
      is Some(exclusion) {
      return Some(exclusion)
    }
    directory = path
    inherited = rules
  }
  self.include_exclusion(parts[:])
}

///|
// Preserve existing exact-selection and Git diagnostic strings.
async fn PathFilter::reason(
  self : PathFilter,
  relative : String,
  require_file : Bool,
) -> String? {
  self.decision(relative, require_file).map(exclusion => exclusion.reason())
}

///|
/// Apply include/ignore, ancestor pruning and no-follow rules without opening a file.
/// Missing paths are valid because Git diffs and history can describe deletions.
pub async fn PathFilter::allows(self : PathFilter, relative : String) -> Bool {
  self.reason(relative, false) is None
}
