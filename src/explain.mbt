///|
/// One queried path: eligibility precedes source decoding and safety checks.
pub struct PathExplanation {
  path : String
  eligible : Bool
  status : String
  stage : String
  reason : String
  origin : @selection.RuleOrigin?
  finding_count : Int32
  finding_rules : Array[String]
}

///|
/// A bounded query, not a promise that an entire repository fits its quotas.
pub struct SelectionReport {
  paths : Array[PathExplanation]
  security : SecurityStatus
  style : Style
  candidate_count : Int32
  accepted_count : Int32
  read_bytes : Int64
  max_files : Int32
  max_total_size : Int64
}

///|
/// Inspect only requested local paths. Uses the same selection and source safety
/// stages as pack, without tokenizer loading, transforms, templates or Git export.
/// Does not write files or alter any generated context.
pub async fn explain_selection(
  options : Options,
  paths : Array[String],
) -> SelectionReport {
  validate_source_limits(options)
  if options.remote is Some(_) ||
    options.remote_branch is Some(_) ||
    paths.length() > 256 ||
    paths.any(path => @utf8.encode(path).length() > 4096) {
    raise ConfigurationError
  }
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
    paths,
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
  let results : Array[PathExplanation] = []
  let mut accepted = 0
  let mut read_bytes = 0L
  let mut excluded_secrets = false
  let mut since_timer_poll = 0
  for decision in selected.decisions {
    if !decision.eligible {
      results.push({
        path: decision.path,
        eligible: false,
        status: "excluded",
        stage: "selection",
        reason: decision.reason,
        origin: decision.origin,
        finding_count: 0,
        finding_rules: [],
      })
      continue
    }
    if since_timer_poll >= 32 {
      @async.sleep(0)
      since_timer_poll = 0
    } else {
      @async.pause()
      since_timer_poll += 1
    }
    guard candidates.get(decision.path) is Some(candidate) else {
      raise SelectionError
    }
    let screened = read_screened(
      candidate,
      options,
      options.max_total_size - read_bytes,
    )
    read_bytes += screened.read_bytes
    let rules : Array[String] = []
    for finding in screened.findings {
      if !rules.contains(finding.rule) {
        rules.push(finding.rule)
      }
    }
    rules.sort()
    let (status, stage, reason) = match screened.result {
      Loaded(_) => {
        accepted += 1
        ("accepted", "complete", "Accepted")
      }
      Skipped("SecurityFinding") => {
        excluded_secrets = true
        ("excluded", "security", "SecurityFinding")
      }
      Skipped("UnrepresentableText") =>
        ("excluded", "format", "UnrepresentableText")
      Skipped(reason) => ("excluded", "input", reason)
    }
    results.push({
      path: decision.path,
      eligible: true,
      status,
      stage,
      reason,
      origin: decision.origin,
      finding_count: screened.findings.length(),
      finding_rules: rules,
    })
  }
  {
    paths: results,
    security: if !options.security_check {
      Disabled
    } else if excluded_secrets {
      Excluded
    } else {
      Passed
    },
    style: options.style,
    candidate_count: selected.selection.files.length(),
    accepted_count: accepted,
    read_bytes,
    max_files: options.max_files,
    max_total_size: options.max_total_size,
  }
}

///|
/// Machine-safe projection: no file bodies, rule text or absolute rule paths.
pub fn SelectionReport::to_json(self : SelectionReport) -> Json {
  let security = match self.security {
    Passed => "passed"
    Excluded => "excluded"
    Disabled => "disabled"
  }
  let style = match self.style {
    Xml => "xml"
    Markdown => "markdown"
    Json => "json"
    Plain => "plain"
  }
  let mut findings = 0
  for path in self.paths {
    findings += path.finding_count
  }
  let paths : Array[Json] = self.paths.map(path => {
    let origin : Json = match path.origin {
      None => Json::null()
      Some(origin) => {
        let source : Json = match origin.source {
          None => Json::null()
          Some(value) => Json(value)
        }
        let line : Json = match origin.line {
          None => Json::null()
          Some(value) => Json(value)
        }
        let index : Json = match origin.index {
          None => Json::null()
          Some(value) => Json(value)
        }
        { "kind": origin.kind, "source": source, "line": line, "index": index }
      }
    }
    {
      "path": path.path,
      "eligible": path.eligible,
      "status": path.status,
      "stage": path.stage,
      "reason": path.reason,
      "origin": origin,
      "findingCount": path.finding_count,
      "findingRules": path.finding_rules,
    }
  })
  {
    "schemaVersion": 1,
    "operation": "explain_selection",
    "scope": "requested-paths",
    "style": style,
    "security": {
      "status": security,
      "enabled": !(self.security is Disabled),
      "findings": findings,
    },
    "paths": paths,
    "counts": {
      "requestedPaths": self.paths.length(),
      "candidates": self.candidate_count,
      "accepted": self.accepted_count,
      "excluded": self.paths.length() - self.accepted_count,
    },
    "readBytes": self.read_bytes.to_string(),
    "limits": {
      "maxFiles": self.max_files,
      "maxTotalSize": self.max_total_size.to_string(),
    },
  }
}
