///|
priv struct Walker {
  filter : PathFilter
  max_files : Int32
  files : Array[Candidate]
  skipped : Array[Skipped]
}

///|
fn Walker::skip(self : Walker, relative : String, reason : String) -> Unit {
  self.skipped.push({ path: relative, reason, })
}

///|
async fn Walker::walk(
  self : Walker,
  directory : String,
  inherited : Array[Rule],
) -> Unit {
  let rules = local_rules(directory, inherited, self.filter.options)
  let names = @fs.readdir(directory, include_hidden=true, sort=false)
  for name in names {
    // readdir excludes '.'/'..'; never accept path components as names.
    if name == "." || name == ".." || name.contains("/") {
      raise SelectionError::InvalidRoot(directory)
    }
    let path = join(directory, name)
    let relative = within(path, self.filter.root).unwrap()
    let kind = @fs.kind(path, follow_symlink=false)
    if type_exclusion(Some(kind)) is Some(exclusion) {
      self.skip(relative, exclusion.reason())
      continue
    }
    let is_dir = kind == Directory
    let parts = relative.split("/").map(p => p.to_owned()).collect()
    if self.filter.exclusion(path, path, parts[:], is_dir, rules)
      is Some(exclusion) {
      self.skip(relative, exclusion.reason())
      continue
    }
    if is_dir {
      self.walk(path, rules)
    } else if self.filter.include_exclusion(parts[:]) is Some(exclusion) {
      self.skip(relative, exclusion.reason())
    } else {
      if self.files.length() >= self.max_files {
        raise SelectionError::FileLimitExceeded(limit=self.max_files)
      }
      self.files.push({ path, relative, })
    }
  }
}

///|
async fn selection_root(root : String) -> String {
  let mut input = separators(root)
  if !absolute(input) {
    raise SelectionError::InvalidRoot(root)
  }
  // Strip trailing separators/dots before no-follow lstat. A trailing slash or
  // '/.' must not hide a symlink in the root's final meaningful component.
  while true {
    if input.has_suffix("/.") {
      input = input[:input.length() - 2].to_owned()
      continue
    }
    if input.has_suffix("/") && input.length() > 1 && !drive_root(input) {
      input = input[:input.length() - 1].to_owned()
      continue
    }
    break
  }
  if input == "" {
    input = "/"
  } else if drive_prefix(input) {
    input += "/"
  }
  if optional_kind(input) != Some(Directory) {
    raise SelectionError::InvalidRoot(root)
  }
  canonical(input)
}

///|
/// Discover files without opening candidate bodies. With file_paths, inspect only
/// literal root-relative entries and their ancestors, never recurse directories.
/// Ignore files are read strictly; I/O and cancellation propagate unchanged.
/// Files and skips are sorted by UTF-8 bytes of root-relative paths.
/// max_files bounds filtered regular candidates before appending, not accepted bodies.
pub async fn select(
  root : String,
  options : SelectionOptions,
  file_paths~ : Array[String]? = None,
  max_files~ : Int32 = 2147483647,
) -> Selection {
  if max_files < 0 {
    raise SelectionError::FileLimitExceeded(limit=max_files)
  }
  let paths = exact_paths(file_paths)
  let root = selection_root(root)
  if paths is Some(paths) {
    return select_exact(root, options, paths, Some(paths), max_files).selection
  }
  let filter = make_path_filter(root, options, None)
  let walker : Walker = { filter, max_files, files: [], skipped: [], }
  match filter.blocked {
    Some(rule) => walker.skip(".", RuleFile(rule, true).reason())
    None => walker.walk(root, filter.inherited)
  }
  walker.files.sort_by((a, b) => utf8_compare(a.relative, b.relative))
  walker.skipped.sort_by((a, b) => utf8_compare(a.path, b.path))
  { root, files: walker.files, skipped: walker.skipped, }
}
