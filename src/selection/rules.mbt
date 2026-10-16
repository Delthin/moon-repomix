///|
priv struct Rule {
  pattern : Pattern
  base : String
  negative : Bool
  source : String
  line : Int32
}

///|
// Git removes only unescaped trailing spaces; leading spaces are significant.
fn trim_rule_line(line : String) -> String {
  let mut end = line.length()
  if end > 0 && line[end - 1] == '\r' {
    end -= 1
  }
  while end > 0 && line[end - 1] == ' ' {
    let mut slashes = 0
    let mut pos = end - 1
    while pos > 0 && line[pos - 1] == '\\' {
      slashes += 1
      pos -= 1
    }
    if slashes % 2 == 1 {
      break
    }
    end -= 1
  }
  line[:end].to_owned()
}

///|
async fn rule_text(path : String) -> String? {
  match optional_kind(path) {
    None => None
    Some(Regular) => Some(@utf8.decode(@fs.read_file(path).binary()))
    Some(_) => raise SelectionError::InvalidRuleFile(path)
  }
}

///|
async fn load_rules(base : String, name : String, rules : Array[Rule]) -> Unit {
  let source = join(base, name)
  if rule_text(source) is Some(text) {
    for index, raw in text.split("\n").collect() {
      let line = trim_rule_line(raw.to_owned())
      if line == "" || line.has_prefix("#") {
        continue
      }
      let negative = line.has_prefix("!")
      let pattern = if negative { line[1:].to_owned() } else { line }
      rules.push({
        pattern: compile_pattern(pattern, source, index + 1, false),
        base,
        negative,
        source,
        line: index + 1,
      })
    }
  }
}

///|
fn ignored_by(rules : Array[Rule], path : String, is_dir : Bool) -> Rule? {
  let mut matched : Rule? = None
  for rule in rules {
    if within(path, rule.base) is Some(relative) &&
      relative != "" &&
      rule.pattern.matches(relative, is_dir) {
      matched = if rule.negative { None } else { Some(rule) }
    }
  }
  matched
}

///|
// Every metadata component is checked before reading through it; rules never
// follow symlinks (including linked info directories and linked gitdirs).
async fn checked_metadata_dir(path : String) -> Bool {
  let up = parent(path)
  if up != path && !checked_metadata_dir(up) {
    return false
  }
  match optional_kind(path) {
    None => false
    Some(Directory) => true
    _ => raise SelectionError::InvalidGitMetadata(path)
  }
}

///|
async fn git_exclude(
  base : String,
  marker : @fs.FileKind,
  rules : Array[Rule],
) -> Unit {
  let dotgit = join(base, ".git")
  let gitdir = match marker {
    Directory => dotgit
    Regular => {
      let text = rule_text(dotgit).unwrap().trim_end(chars="\r\n").to_owned()
      if !text.has_prefix("gitdir: ") {
        raise SelectionError::InvalidGitMetadata(dotgit)
      }
      let target = text[8:].to_owned()
      if target == "" || target.contains("\n") {
        raise SelectionError::InvalidGitMetadata(dotgit)
      }
      normalize(
        if absolute(separators(target)) {
          target
        } else {
          join(base, target)
        },
      )
    }
    _ => raise SelectionError::InvalidGitMetadata(dotgit)
  }
  if !checked_metadata_dir(gitdir) {
    raise SelectionError::InvalidGitMetadata(gitdir)
  }
  let common = match rule_text(join(gitdir, "commondir")) {
    None => gitdir
    Some(text) => {
      let target = text.trim_end(chars="\r\n").to_owned()
      if target == "" || target.contains("\n") {
        raise SelectionError::InvalidGitMetadata(join(gitdir, "commondir"))
      }
      normalize(
        if absolute(separators(target)) {
          target
        } else {
          join(gitdir, target)
        },
      )
    }
  }
  if !checked_metadata_dir(common) {
    raise SelectionError::InvalidGitMetadata(common)
  }
  let info = join(common, "info")
  if checked_metadata_dir(info) {
    // The physical source is in Git metadata, but its patterns are based at
    // the worktree root, not at .git/info.
    let loaded : Array[Rule] = []
    load_rules(info, "exclude", loaded)
    for rule in loaded {
      rules.push({ ..rule, base, })
    }
  }
}

///|
async fn inherited_rules(
  root : String,
  options : SelectionOptions,
) -> (Array[Rule], Rule?) {
  let rules : Array[Rule] = []
  if !options.use_gitignore {
    return (rules, None)
  }
  let ancestors : Array[String] = []
  let mut current = root
  while true {
    ancestors.push(current)
    if optional_kind(join(current, ".git")) is Some(marker) {
      git_exclude(current, marker, rules)
      break
    }
    let up = parent(current)
    if up == current {
      break
    }
    current = up
  }
  // Root's files are loaded by walk, together with .ignore/.repomixignore.
  for i = ancestors.length() - 1; i >= 0; i = i - 1 {
    if ignored_by(rules, ancestors[i], true) is Some(rule) {
      return (rules, Some(rule))
    }
    if i > 0 {
      load_rules(ancestors[i], ".gitignore", rules)
    }
  }
  (rules, None)
}

///|
async fn local_rules(
  base : String,
  inherited : Array[Rule],
  options : SelectionOptions,
) -> Array[Rule] {
  let rules = inherited.copy()
  if options.use_gitignore {
    load_rules(base, ".gitignore", rules)
  }
  if options.use_dot_ignore {
    load_rules(base, ".ignore", rules)
    load_rules(base, ".repomixignore", rules)
  }
  rules
}
