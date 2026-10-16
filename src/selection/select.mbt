///|
priv struct Walker {
  options : SelectionOptions
  root : String
  output : String?
  includes : Array[Pattern]
  custom : Array[Pattern]
  defaults : Array[Pattern]
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
  let rules = local_rules(directory, inherited, self.options)
  let names = @fs.readdir(directory, include_hidden=true, sort=false)
  for name in names {
    // readdir excludes '.'/'..'; never accept path components as names.
    if name == "." || name == ".." || name.contains("/") {
      raise SelectionError::InvalidRoot(directory)
    }
    let path = join(directory, name)
    let relative = within(path, self.root).unwrap()
    let kind = @fs.kind(path, follow_symlink=false)
    if kind == SymLink {
      self.skip(relative, "Symlink")
      continue
    }
    if kind != Regular && kind != Directory {
      self.skip(relative, "UnsupportedFileType")
      continue
    }
    let is_dir = kind == Directory
    if self.output is Some(output) && path == output {
      self.skip(relative, "OutputFile")
      continue
    }
    if self.defaults.any(p => p.matches(relative, is_dir)) {
      self.skip(
        relative,
        if is_dir {
          "IgnoredDirectory:default"
        } else {
          "Ignored:default"
        },
      )
      continue
    }
    if self.custom.any(p => p.matches(relative, is_dir)) {
      self.skip(
        relative,
        if is_dir {
          "IgnoredDirectory:custom"
        } else {
          "Ignored:custom"
        },
      )
      continue
    }
    if ignored_by(rules, path, is_dir) is Some(rule) {
      self.skip(
        relative,
        "\{if is_dir { "IgnoredDirectory" } else { "Ignored" }}:\{rule.source}:\{rule.line}",
      )
      continue
    }
    if is_dir {
      self.walk(path, rules)
    } else if included(self.includes, relative) {
      self.files.push({ path, relative, })
    } else {
      self.skip(relative, "NotIncluded")
    }
  }
}

///|
/// Traverse an absolute ordinary directory without opening candidate files.
/// Ignore files are read strictly; I/O and cancellation propagate unchanged.
/// Files and skips are sorted by UTF-8 bytes of root-relative paths.
pub async fn select(root : String, options : SelectionOptions) -> Selection {
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
  let root = canonical(input)
  let includes = options.include_patterns.map(p => {
    compile_pattern(p, "include", 0, true)
  })
  let custom = options.ignore.map(p => compile_pattern(p, "ignore", 0, true))
  let defaults = if options.use_default_patterns {
    [".git", ".hg", ".svn", "node_modules", "_build", ".DS_Store"].map(p => {
      compile_pattern(p, "default", 0, true)
    })
  } else {
    []
  }
  let output = match options.output {
    None => None
    Some(path) => {
      if !absolute(separators(path)) {
        raise SelectionError::InvalidOutput(path)
      }
      Some(normalize(output_identity(separators(path))))
    }
  }
  let walker : Walker = {
    options,
    root,
    output,
    includes,
    custom,
    defaults,
    files: [],
    skipped: [],
  }
  let (rules, blocked) = inherited_rules(root, options)
  match blocked {
    Some(rule) =>
      walker.skip(".", "IgnoredDirectory:\{rule.source}:\{rule.line}")
    None => walker.walk(root, rules)
  }
  walker.files.sort_by((a, b) => utf8_compare(a.relative, b.relative))
  walker.skipped.sort_by((a, b) => utf8_compare(a.path, b.path))
  { root, files: walker.files, skipped: walker.skipped, }
}
