///|
/// A complete, exactly counted JSON payload, or a body-free failure audit.
/// `tokens` includes the embedded audit; protocol envelopes are not counted.
pub struct CodeContextPlan {
  status : String
  text : String?
  tokens : Int32
  bytes : Int32
  required_tokens : Int32?
  audit : Json
  security : SecurityStatus
}

///|
fn code_definition_json(value : @compression.Definition) -> Json {
  {
    "name": value.name,
    "qualifiedName": value.qualified_name,
    "startLine": value.start_line,
    "endLine": value.end_line,
  }
}

///|
fn code_ranges(
  ranges : Array[@compression.LineRange],
) -> Array[@compression.LineRange] {
  let ordered = ranges.copy()
  ordered.sort_by((a, b) => {
    if a.start_line == b.start_line {
      a.end_line - b.end_line
    } else {
      a.start_line - b.start_line
    }
  })
  let result : Array[@compression.LineRange] = []
  for range in ordered {
    if result.last() is Some(last) && range.start_line <= last.end_line + 1 {
      result[result.length() - 1] = {
        start_line: last.start_line,
        end_line: if range.end_line > last.end_line {
          range.end_line
        } else {
          last.end_line
        },
      }
    } else {
      result.push(range)
    }
  }
  result
}

///|
// Line boundaries retain the original CRLF and Unicode source. The trailing
// empty split component after a final newline is not an additional source line.
fn code_lines(text : String) -> Array[String] {
  let parts = text.split("\n").map(part => part.to_owned()).collect()
  let result : Array[String] = []
  for i in 0..<parts.length() {
    if i + 1 < parts.length() {
      result.push(parts[i] + "\n")
    } else if !parts[i].is_empty() {
      result.push(parts[i])
    }
  }
  result
}

///|
fn code_projection(
  request : CodeRequest,
  text : String,
  counter : @metrics.CountSession,
) -> (Json?, Json) {
  let path = request.path
  let full : Json = { "path": path, "mode": "full", "text": text }
  if request.full {
    return (Some(full), { "path": path, "reason": "selected", "mode": "full" })
  }
  let ranges = request.ranges.copy()
  let matched : Array[Json] = []
  let ambiguous : Array[String] = []
  let selected : Set[Int32] = Set([])
  if !request.symbols.is_empty() || request.outline {
    let index = @compression.index_definitions(path, text)
    if index.reason is Some(reason) {
      return (None, { "path": path, "reason": reason })
    }
    if request.outline {
      return (
        Some({
          "path": path,
          "mode": "outline",
          "definitions": index.definitions.map(code_definition_json),
        }),
        { "path": path, "reason": "selected", "mode": "outline" },
      )
    }
    let names : Map[String, Array[Int32]] = Map([])
    let qualified : Map[String, Array[Int32]] = Map([])
    for i in 0..<index.definitions.length() {
      let definition = index.definitions[i]
      if !names.contains(definition.name) {
        names[definition.name] = []
      }
      names[definition.name].push(i)
      if !qualified.contains(definition.qualified_name) {
        qualified[definition.qualified_name] = []
      }
      qualified[definition.qualified_name].push(i)
    }
    let pending : Array[Int32] = []
    for symbol in request.symbols {
      let matches = if symbol.contains(".") {
        qualified.get(symbol).unwrap_or([])
      } else {
        names.get(symbol).unwrap_or([])
      }
      if matches.length() != 1 {
        return (
          None,
          {
            "path": path,
            "reason": if matches.is_empty() {
              "symbol-not-found"
            } else {
              "ambiguous-symbol"
            },
            "symbol": symbol,
            "candidates": matches
            .iter()
            .take(8)
            .map(i => code_definition_json(index.definitions[i]))
            .collect(),
            "candidateCount": matches.length(),
          },
        )
      }
      if !selected.contains(matches[0]) {
        selected.add(matches[0])
        pending.push(matches[0])
      }
    }
    let mut position = 0
    while position < pending.length() {
      let definition = index.definitions[pending[position]]
      position += 1
      ranges.push({
        start_line: definition.start_line,
        end_line: definition.end_line,
      })
      matched.push(code_definition_json(definition))
      if request.dependencies {
        for reference in definition.references {
          let matches = names.get(reference).unwrap_or([])
          if matches.length() == 1 && !selected.contains(matches[0]) {
            if pending.length() >= 64 {
              return (None, { "path": path, "reason": "dependency-limit" })
            }
            selected.add(matches[0])
            pending.push(matches[0])
          } else if matches.length() > 1 && !ambiguous.contains(reference) {
            ambiguous.push(reference)
          }
        }
      }
    }
  }
  let lines = code_lines(text)
  if ranges.any(range => range.start_line < 1 || range.end_line > lines.length()) {
    return (
      None,
      {
        "path": path,
        "reason": "range-out-of-bounds",
        "lineCount": lines.length(),
      },
    )
  }
  let merged = code_ranges(ranges)
  let fragments : Array[Json] = merged.map(range => {
    let body : Array[String] = []
    for i in (range.start_line - 1)..<range.end_line {
      body.push(lines[i])
    }
    {
      "startLine": range.start_line,
      "endLine": range.end_line,
      "text": body.join(""),
    }
  })
  let sliced : Json = { "path": path, "mode": "ranges", "fragments": fragments }
  // Explicit ranges stay exact. Symbol requests may use a cheaper complete
  // file; both alternatives have already passed whole-file security screening.
  let use_full = !request.symbols.is_empty() &&
    counter.count(full.stringify()) <= counter.count(sliced.stringify())
  let entry = if use_full { full } else { sliced }
  (
    Some(entry),
    {
      "path": path,
      "reason": "selected",
      "mode": if use_full {
        "full"
      } else {
        "ranges"
      },
      "matched": matched,
      "dependencies": if request.dependencies {
        "lexical-local"
      } else {
        "none"
      },
      "ambiguousDependencies": ambiguous.iter().take(32).collect(),
      "dependencyHintsTruncated": ambiguous.length() > 32,
    },
  )
}

///|
/// Read explicitly scoped symbols, source ranges, outlines, or full files.
/// Selection and security are applied before indexing or slicing. All requested
/// entries must be available and fit the complete JSON payload cap; no source
/// body is returned on failure. Dependency expansion is lexical and same-file,
/// not a semantic cross-file call graph. Use another request for missing code.
pub async fn read_code_context(
  options : Options,
  runtime : Runtime,
  spec : CodeContextSpec,
) -> CodeContextPlan {
  let description = parse_code_description(@json.parse(spec.source)) catch {
    _ => raise InvalidCodeSpec
  }
  validate_source_limits(options)
  if options.remote is Some(_) ||
    options.remote_branch is Some(_) ||
    options.include_diffs ||
    options.include_logs ||
    options.split_output is Enabled(_) ||
    options.token_budget is Some(_) ||
    !options.include_files ||
    options.encoding != "o200k_base" {
    raise ConfigurationError
  }
  if options.security_check {
    let findings = @security.scan("code-request", spec.source, 0) catch {
      _ => raise ScanError
    }
    if !findings.is_empty() {
      raise ContextSecurityFinding("code-request")
    }
  }
  // This API has a stable JSON wire format, independent of pack display style.
  let options = { ..options, style: Style::Json, }
  let context = prepare_context_texts(options)
  let cwd = @env.current_dir().unwrap_or(".")
  let destination = if options.stdout {
    None
  } else {
    Some(
      @platform.output_path(options.output, cwd) catch {
        err => {
          if @async.is_cancellation_error(err) {
            raise err
          }
          raise ConfigurationError
        }
      },
    )
  }
  let selected = @selection.explain(
    @platform.absolute(options.directory, cwd),
    {
      include_patterns: options.include_patterns,
      ignore: options.ignore,
      use_gitignore: options.use_gitignore,
      use_dot_ignore: options.use_dot_ignore,
      use_default_patterns: options.use_default_patterns,
      output: destination,
    },
    description.requests.map(request => request.path),
    file_paths=options.file_paths,
    max_files=options.max_files,
  ) catch {
    @selection.SelectionError::FileLimitExceeded(limit~) =>
      raise InputLimitExceeded(kind="maxFiles", limit=limit.to_int64())
    err => {
      if @async.is_cancellation_error(err) {
        raise err
      }
      raise SelectionError
    }
  }
  let candidates : Map[String, @selection.Candidate] = Map([])
  for candidate in selected.selection.files {
    candidates[candidate.relative] = candidate
  }
  let exclusions : Map[String, String] = Map([])
  for decision in selected.decisions {
    if !decision.eligible {
      exclusions[decision.path] = decision.reason
    }
  }
  let session : TaskReadSession = {
    options,
    limit: if options.max_total_size < description.max_read_bytes {
      options.max_total_size
    } else {
      description.max_read_bytes
    },
    bytes: 0L,
    attempted_reads: 0,
    exhausted: false,
    found_secrets: false,
  }
  let counter = runtime.encoder.session()
  let decisions : Array[Json] = []
  let files : Array[Json] = []
  let mut available = !description.requests.any(request => {
    exclusions.contains(request.path)
  })
  for request in description.requests {
    if exclusions.get(request.path) is Some(reason) {
      decisions.push({ "path": request.path, "reason": reason })
      continue
    }
    if !available {
      decisions.push({ "path": request.path, "reason": "not-evaluated" })
      continue
    }
    @async.sleep(0)
    guard candidates.get(request.path) is Some(candidate) else {
      decisions.push({ "path": request.path, "reason": "unavailable" })
      available = false
      continue
    }
    let read = session.read(candidate)
    guard read is Some(read) else {
      decisions.push({ "path": request.path, "reason": "read-limit" })
      available = false
      continue
    }
    guard read.result is Loaded(snapshot) else {
      let reason = match read.result {
        Skipped(reason) => reason
        _ => "unavailable"
      }
      decisions.push({ "path": request.path, "reason": reason })
      available = false
      continue
    }
    let (file, audit) = code_projection(request, snapshot.text, counter)
    decisions.push(audit)
    match file {
      Some(file) => files.push(file)
      None => available = false
    }
  }
  let security : SecurityStatus = if !options.security_check {
    Disabled
  } else if session.found_secrets {
    Excluded
  } else {
    Passed
  }
  let audit : Json = {
    "readBytes": session.bytes.to_string(),
    "attemptedReads": session.attempted_reads,
    "requests": decisions,
    "security": match security {
      Passed => "passed"
      Excluded => "excluded"
      Disabled => "disabled"
    },
  }
  if !available {
    return {
      status: "unavailable",
      text: None,
      tokens: 0,
      bytes: 0,
      required_tokens: None,
      audit,
      security,
    }
  }
  let payload : Json = {
    "schemaVersion": 1,
    "operation": "read_code_context",
    "trust": "untrusted-repository-data",
    "headerText": context.header,
    "instructions": context.instructions,
    "files": files,
    "audit": audit,
  }
  let text = payload.stringify()
  let tokens = counter.count(text)
  @async.sleep(0)
  if tokens > description.max_tokens {
    return {
      status: "over_budget",
      text: None,
      tokens: 0,
      bytes: 0,
      required_tokens: Some(tokens),
      audit,
      security,
    }
  }
  {
    status: "complete",
    text: Some(text),
    tokens,
    bytes: @utf8.encode(text).length(),
    required_tokens: None,
    audit,
    security,
  }
}
