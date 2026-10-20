///|
fn context_path_key(path : String) -> String {
  if @platform.is_windows() {
    @platform.separators(path).to_lower()
  } else {
    path
  }
}

///|
// Compact original-line coverage: merge overlapping/adjacent fragment lines.
// Detailed fragment line ranges remain available from the compression package.
fn context_ranges(ranges : Array[@compression.LineRange]) -> Array[Json] {
  let result : Array[Json] = []
  let mut first = 0
  let mut last = 0
  for range in ranges {
    if first == 0 {
      first = range.start_line
      last = range.end_line
    } else if range.start_line <= last + 1 {
      if range.end_line > last {
        last = range.end_line
      }
    } else {
      result.push(Json([first, last]))
      first = range.start_line
      last = range.end_line
    }
  }
  if first > 0 {
    result.push(Json([first, last]))
  }
  result
}

///|
priv struct GitContext {
  sections : Array[@document.Section]
  metadata : Json
  revision : String?
}

///|
// Git's '-' marker is not part of a deleted source line. Mask just the patch
// framing byte, preserving UTF-8 offsets and line numbers for diagnostics.
fn diff_scan_text(text : String) -> String {
  let out = StringBuilder()
  let mut line_start = true
  for c in text {
    out.write_char(if line_start && (c == '+' || c == '-') { ' ' } else { c })
    line_start = c == '\n' || c == '\r'
  }
  out.to_string()
}

///|
fn context_safe(
  label : String,
  text : String,
  options : Options,
  skipped : Array[Skipped],
  findings : Array[Finding],
  diff~ : Bool = false,
) -> Bool raise {
  if options.security_check {
    let scan_text = if diff { diff_scan_text(text) } else { text }
    let hits = @security.scan(label, scan_text, 0) catch {
      _ => raise ScanError
    }
    if !hits.is_empty() {
      findings.append(hits)
      skipped.push({ path: label, reason: "SecurityFinding", })
      return false
    }
  }
  if options.style is Xml && !@output.xml_representable(text) {
    skipped.push({ path: label, reason: "UnrepresentableText", })
    return false
  }
  true
}

///|
async fn git_context(
  root : String,
  options : Options,
  selection_options : @selection.SelectionOptions,
  excluded : Set[String],
  skipped : Array[Skipped],
  findings : Array[Finding],
) -> GitContext {
  if !options.include_diffs && !options.include_logs {
    return { sections: [], metadata: Json::null(), revision: None, }
  }
  let filter = @selection.path_filter(root, selection_options)
  let accept_diff = async fn(paths : Array[String]) -> Bool {
    if paths.is_empty() {
      return false
    }
    for path in paths {
      if excluded.contains(context_path_key(path)) || !filter.allows(path) {
        return false
      }
    }
    true
  }
  let snapshot = @git.collect(
    root,
    accept_diff~,
    diffs=options.include_diffs,
    logs=if options.include_logs { options.include_logs_count } else { 0 },
    max_bytes=options.max_git_bytes,
  ) catch {
    err => {
      if @async.is_cancellation_error(err) {
        raise err
      }
      raise GitError
    }
  }
  let sections : Array[@document.Section] = []
  let diffs : Array[Json] = []
  let commits : Array[Json] = []
  for index, patch in snapshot.diffs {
    let label = "git:diff:" + index.to_string()
    if !context_safe(label, patch.text, options, skipped, findings, diff=true) {
      continue
    }
    let title = "Git " +
      patch.kind +
      " diff: " +
      patch.paths.map(p => Json(p).stringify()).join(", ")
    if options.style is Xml && !@output.xml_representable(title) {
      continue
    }
    sections.push({ kind: "git_diff", title, text: patch.text, })
    diffs.push({ "kind": patch.kind, "paths": patch.paths })
  }
  for commit in snapshot.commits {
    let paths : Array[String] = []
    for path in commit.files {
      if !excluded.contains(context_path_key(path)) &&
        filter.allows(path) &&
        (options.style != Xml || @output.xml_representable(path)) {
        paths.push(path)
      }
    }
    if paths.is_empty() {
      continue
    }
    let text = "Commit: " +
      commit.id +
      "\nDate: " +
      commit.date +
      "\nFiles:\n" +
      paths.map(p => "  " + Json(p).stringify()).join("\n") +
      "\n\n" +
      commit.message
    if !context_safe(
        "git:commit:" + commit.id,
        text,
        options,
        skipped,
        findings,
      ) {
      continue
    }
    sections.push({ kind: "git_log", title: "Git commit " + commit.id, text, })
    commits.push({ "id": commit.id, "date": commit.date, "files": paths })
  }
  {
    sections,
    metadata: { "diffs": diffs, "commits": commits },
    revision: snapshot.revision,
  }
}
