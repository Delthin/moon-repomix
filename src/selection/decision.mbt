///|
// One structural exclusion, rendered either as the legacy diagnostic or as a
// safe query decision. Keep rule text and absolute rule paths inside this type.
priv enum Exclusion {
  Fixed(String)
  Pattern(String, Int32, Bool)
  RuleFile(Rule, Bool)
}

///|
fn ignored_reason(is_dir : Bool) -> String {
  if is_dir {
    "IgnoredDirectory"
  } else {
    "Ignored"
  }
}

///|
fn Exclusion::reason(self : Exclusion) -> String {
  match self {
    Fixed(reason) => reason
    Pattern(kind, _, is_dir) => "\{ignored_reason(is_dir)}:\{kind}"
    RuleFile(rule, is_dir) =>
      "\{ignored_reason(is_dir)}:\{rule.source}:\{rule.line}"
  }
}

///|
fn Exclusion::decision(
  self : Exclusion,
  root : String,
  path : String,
) -> PathDecision {
  let (reason, origin) = match self {
    Fixed(reason) => (reason, None)
    Pattern(kind, index, is_dir) =>
      (
        ignored_reason(is_dir),
        Some({ kind, source: None, line: None, index: Some(index), }),
      )
    RuleFile(rule, is_dir) => {
      let kind = match basename(rule.source) {
        ".gitignore" => "gitignore"
        ".ignore" => "dot-ignore"
        ".repomixignore" => "repomixignore"
        _ => "git-info-exclude"
      }
      (
        ignored_reason(is_dir),
        Some({
          kind,
          source: within(rule.source, root),
          line: Some(rule.line),
          index: None,
        }),
      )
    }
  }
  { path, eligible: false, reason, origin, }
}

///|
fn candidate_decision(path : String) -> PathDecision {
  { path, eligible: true, reason: "Candidate", origin: None, }
}

///|
fn type_exclusion(kind : @fs.FileKind?) -> Exclusion? {
  match kind {
    Some(SymLink) => Some(Fixed("Symlink"))
    Some(kind) if kind != Regular && kind != Directory =>
      Some(Fixed("UnsupportedFileType"))
    _ => None
  }
}

///|
// The walker and exact/Git paths share the same ordered exclusion layers.
// The caller checks type, spelling and component position before this function.
fn PathFilter::exclusion(
  self : PathFilter,
  path : String,
  output_path : String,
  parts : ArrayView[String],
  is_dir : Bool,
  rules : Array[Rule],
) -> Exclusion? {
  if self.output == Some(output_path) {
    return Some(Fixed("OutputFile"))
  }
  for index, pattern in self.defaults {
    if pattern.matches_parts(parts, is_dir) {
      return Some(Pattern("default", index, is_dir))
    }
  }
  for index, pattern in self.custom {
    if pattern.matches_parts(parts, is_dir) {
      return Some(Pattern("custom", index, is_dir))
    }
  }
  ignored_by(rules, path, is_dir).map(rule => RuleFile(rule, is_dir))
}

///|
fn PathFilter::include_exclusion(
  self : PathFilter,
  parts : ArrayView[String],
) -> Exclusion? {
  if included_parts(self.includes, parts) {
    None
  } else {
    Some(Fixed("NotIncluded"))
  }
}
