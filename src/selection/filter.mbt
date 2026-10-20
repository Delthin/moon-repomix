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
  blocked : Bool
  output : String?
  cache : Map[String, Array[Rule]]
}

///|
/// The root is the canonical root returned by `select`.
pub async fn path_filter(
  root : String,
  options : SelectionOptions,
) -> PathFilter {
  if !absolute(root) || optional_kind(root) != Some(Directory) {
    raise SelectionError::InvalidRoot(root)
  }
  let (inherited, blocked) = inherited_rules(root, options)
  let output = match options.output {
    None => None
    Some(path) => Some(normalize(output_identity(path)))
  }
  {
    root,
    options,
    includes: options.include_patterns.map(p => {
      compile_pattern(p, "include", 0, true)
    }),
    custom: options.ignore.map(p => compile_pattern(p, "ignore", 0, true)),
    defaults: if options.use_default_patterns {
      [".git", ".hg", ".svn", "node_modules", "_build", ".DS_Store"].map(p => {
        compile_pattern(p, "default", 0, true)
      })
    } else {
      []
    },
    inherited,
    blocked: blocked is Some(_),
    output,
    cache: Map([]),
  }
}

///|
/// Apply include/ignore, ancestor pruning and no-follow rules without opening a file.
/// Missing paths are valid because Git diffs and history can describe deletions.
pub async fn PathFilter::allows(self : PathFilter, relative : String) -> Bool {
  if self.blocked ||
    relative == "" ||
    absolute(relative) ||
    !git_path_spelling(relative) ||
    relative.contains("\u{0}") {
    return false
  }
  let parts = relative.split("/").map(p => p.to_owned()).collect()
  if parts.any(p => p == "" || p == "." || p == "..") {
    return false
  }
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
      Some(SymLink) => return false
      Some(Directory) if !is_dir => return false
      Some(Regular) if is_dir => return false
      Some(kind) if kind != Regular && kind != Directory => return false
      _ => ()
    }
    if self.defaults.any(p => p.matches(partial, is_dir)) ||
      self.custom.any(p => p.matches(partial, is_dir)) ||
      ignored_by(rules, path, is_dir) is Some(_) {
      return false
    }
    if !is_dir &&
      self.output is Some(output) &&
      normalize(output_identity(path)) == output {
      return false
    }
    directory = path
    inherited = rules
  }
  included(self.includes, relative)
}
