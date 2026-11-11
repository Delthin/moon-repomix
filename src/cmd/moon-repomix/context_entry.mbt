///|
suberror ContextEntryError {
  InvalidRequest
  RequestTooLarge
  StaleCodeSession
  ResponseTooLarge
}

///|
priv struct ContextHost {
  mut session : @repomix.CodeContextSession?
  mut latest : String?
  mut sequence : Int32
  prefix : String
}

///|
priv struct ContextPending {
  response : Json
  session : @repomix.CodeContextSession?
  latest : String?
  success : Bool
}

///|
fn context_operation(request : @repomix.ContextRequest) -> String {
  match request.operation {
    Task => "plan_task_context"
    Code => "read_code_context"
  }
}

///|
fn context_category(err : Error) -> String {
  match err {
    InvalidRequest
    | @repomix.InvalidContextRequest
    | @repomix.InvalidCodeSpec
    | @repomix.InvalidTaskSpec => "InvalidContextRequest"
    RequestTooLarge => "RequestTooLarge"
    StaleCodeSession => "StaleCodeSession"
    ResponseTooLarge => "ResourceLimit"
    @repomix.CodeRoundLimit => "CodeRoundLimit"
    @repomix.CodeBudgetExhausted => "CodeBudgetExhausted"
    @repomix.ContextTextError(_) => "ContextTextError"
    @repomix.ContextSecurityFinding(_) => "ContextSecurityError"
    @repomix.InputLimitExceeded(kind=_, limit=_) => "InputLimitError"
    @repomix.SelectionError => "SelectionError"
    @repomix.ScanError => "ScanError"
    Configuration | @repomix.ConfigurationError => "ConfigurationError"
    Write => "OutputError"
    _ => "OperationError"
  }
}

///|
fn context_security(status : @repomix.SecurityStatus) -> Json {
  // Root plans expose a status, not a finding count. Do not invent a zero count.
  let name = match status {
    Passed => "passed"
    Excluded => "excluded"
    Disabled => "disabled"
  }
  { "status": name, "enabled": !(status is Disabled) }
}

///|
fn context_error(operation : String, category : String) -> Json {
  {
    "schemaVersion": 1,
    "operation": operation,
    "ok": false,
    "status": "error",
    "error": { "category": category },
  }
}

///|
fn context_parse(bytes : Bytes) -> @repomix.ContextRequest raise {
  let text = @utf8.decode(bytes, ignore_bom=true) catch {
    _ => raise InvalidRequest
  }
  let value = @json.parse(text) catch { _ => raise InvalidRequest }
  @repomix.ContextRequest::from_json(value)
}

///|
async fn context_file(path : String) -> Bytes {
  try {
    if @fs.kind(path, follow_symlink=false) != @fs.Regular {
      raise InvalidRequest
    }
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    let buffer = @buffer.Buffer(size_hint=4096)
    for ;; {
      let remaining = 65536 - buffer.length()
      let size = if remaining >= 4096 { 4096 } else { remaining + 1 }
      match @io.Reader::read_some(file, max_len=size) {
        None => break
        Some(bytes) => {
          if bytes.length() > remaining {
            raise RequestTooLarge
          }
          buffer.write_bytes(bytes)
        }
      }
    }
    buffer.to_bytes()
  } catch {
    err => {
      if @async.is_being_cancelled() {
        raise err
      }
      match err {
        RequestTooLarge => raise RequestTooLarge
        _ => raise InvalidRequest
      }
    }
  }
}

///|
priv struct ContextLines {
  mut pending : Bytes
  mut eof : Bool
}

///|
// Retain at most one bounded line and a single oversize probe. Never drain an
// untrusted unterminated stream after a limit error.
async fn ContextLines::next(self : ContextLines) -> Bytes? {
  for ;; {
    if self.pending.find(b"\n") is Some(end) {
      if end > 65536 {
        raise RequestTooLarge
      }
      let line = self.pending[:end].to_owned()
      self.pending = self.pending[end + 1:].to_owned()
      return Some(line)
    }
    if self.pending.length() > 65536 {
      raise RequestTooLarge
    }
    if self.eof {
      if self.pending.is_empty() {
        return None
      }
      let line = self.pending
      self.pending = b""
      return Some(line)
    }
    let remaining = 65536 - self.pending.length()
    let size = if remaining >= 4096 { 4096 } else { remaining + 1 }
    match @io.Reader::read_some(@stdio.stdin, max_len=size) {
      None => self.eof = true
      Some(bytes) => self.pending = self.pending + bytes
    }
  }
}

///|
async fn context_plan(
  request : @repomix.ContextRequest,
  options : @config.Options,
  runtime : @repomix.Runtime,
  host : ContextHost,
  resumable : Bool,
) -> ContextPending {
  let operation = context_operation(request)
  // Resolve the publication destination at the adapter boundary. Root also uses
  // it for self-output exclusion; a bad parent is an output failure, not a spec.
  if !options.stdout {
    ignore(
      @platform.output_path(options.output, @env.current_dir().unwrap_or(".")),
    ) catch {
      err => {
        if @async.is_being_cancelled() {
          raise err
        }
        raise Write
      }
    }
  }
  match request.operation {
    Task => {
      let spec = @repomix.TaskContextSpec::from_json(request.spec_json())
      let plan = @repomix.plan_task_context(options, runtime, spec)
      let success = (
          plan.status == "complete" || plan.status == "with_omissions"
        ) &&
        plan.text is Some(_)
      let fields : Map[String, Json] = {
        "schemaVersion": Json(1),
        "operation": Json(operation),
        "ok": Json(success),
        "status": Json(plan.status),
        "tokens": Json(plan.tokens),
        "bytes": Json(plan.bytes),
        "security": context_security(plan.security),
        "audit": plan.audit,
        "auditText": Json(plan.audit_text),
        "auditTokens": Json(plan.audit_tokens),
        "auditBytes": Json(plan.audit_bytes),
        "auditIncludedInText": Json(false),
      }
      if plan.text is Some(text) {
        fields["text"] = Json(text)
      }
      { response: Json::object(fields), success, session: None, latest: None, }
    }
    Code => {
      let (session, spec) = match request.continue_from {
        Some(id) => {
          guard resumable &&
            host.latest == Some(id) &&
            host.session is Some(session) else {
            raise StaleCodeSession
          }
          (session, session.request(request.spec_json()))
        }
        None => {
          let spec = @repomix.CodeContextSpec::from_json(request.spec_json())
          (@repomix.CodeContextSession::new(spec.max_tokens), spec)
        }
      }
      let plan = @repomix.read_code_context(options, runtime, spec)
      let success = plan.status == "complete" && plan.text is Some(_)
      let candidate = session.advance(plan)
      let fields : Map[String, Json] = {
        "schemaVersion": Json(1),
        "operation": Json(operation),
        "ok": Json(success),
        "status": Json(plan.status),
        "tokens": Json(plan.tokens),
        "bytes": Json(plan.bytes),
        "security": context_security(plan.security),
        "audit": plan.audit,
        "auditIncludedInText": Json(true),
      }
      if plan.required_tokens is Some(tokens) {
        fields["requiredTokens"] = Json(tokens)
      }
      let latest = if success {
        let id = host.prefix + "-" + host.sequence.to_string()
        fields["runId"] = Json(id)
        fields["round"] = Json(candidate.rounds)
        fields["sessionTokens"] = Json(candidate.spent)
        fields["remainingTokens"] = Json(candidate.remaining())
        fields["maxTokens"] = Json(candidate.limit)
        fields["canContinue"] = Json(resumable && candidate.can_continue())
        Some(id)
      } else {
        None
      }
      if plan.text is Some(text) {
        fields["text"] = Json(text)
      }
      {
        response: Json::object(fields),
        success,
        session: Some(candidate),
        latest,
      }
    }
  }
}

///|
async fn context_write_stdout(text : String, state : RunState) -> Unit {
  state.publication = "unknown"
  @stdio.stdout.write(text) catch {
    err => {
      if @async.is_being_cancelled() {
        raise err
      }
      raise Write
    }
  }
  state.publication = "committed"
}

///|
async fn context_publish(
  pending : ContextPending,
  options : @config.Options,
  state : RunState,
  host : ContextHost,
) -> Int32 {
  let text = pending.response.stringify() + "\n"
  if @utf8.encode(text).length() > 16777216 {
    raise ResponseTooLarge
  }
  @async.sleep(0)
  if pending.success || options.stdout {
    state.publication = "unknown"
    if options.stdout {
      context_write_stdout(text, state)
    } else {
      let cwd = @env.current_dir().unwrap_or(".")
      let path = @platform.output_path(options.output, cwd) catch {
        _ => {
          state.publication = "not_started"
          raise Write
        }
      }
      @platform.commit(path, text) catch {
        err => {
          if @async.is_being_cancelled() {
            raise err
          }
          state.publication = "not_started"
          raise Write
        }
      }
    }
    state.publication = "committed"
  }
  if pending.success {
    host.session = pending.session
    host.latest = pending.latest
    host.sequence += 1
  }
  let code = if pending.success { 0 } else { 1 }
  if state.report_json {
    finish_report(() => {
      write_json_report({
        "schemaVersion": 1,
        "operation": state.operation,
        "status": if pending.success {
          "ok"
        } else {
          "error"
        },
        "resultStatus": match pending.response {
          Object(fields) => fields["status"]
          _ => Json::null()
        },
        "publication": state.publication,
        "exitCode": code,
      })
    })
  }
  code
}

///|
async fn run_context(
  cli : @config.Cli,
  options : @config.Options,
  runtime : @repomix.Runtime,
  state : RunState,
) -> Int32 {
  let host : ContextHost = {
    session: None,
    latest: None,
    sequence: 1,
    prefix: "cli-" + @env.now().to_string(),
  }
  let lines : ContextLines = { pending: b"", eof: false, }
  for ;; {
    state.publication = "not_started"
    state.operation = if cli.context_stdio {
      "context_stdio"
    } else {
      "context_request"
    }
    let mut stop = false
    let code = try {
      let bytes = if cli.context_stdio {
        match lines.next() {
          None => return 0
          Some(bytes) => bytes
        }
      } else {
        context_file(cli.context_request.unwrap())
      }
      let request = context_parse(bytes)
      state.operation = context_operation(request)
      let pending = context_plan(
        request,
        options,
        runtime,
        host,
        cli.context_stdio,
      )
      context_publish(pending, options, state, host)
    } catch {
      err => {
        if @async.is_being_cancelled() {
          raise err
        }
        if err is RequestTooLarge {
          stop = true
        }
        let category = context_category(err)
        // Do not attempt another write after a partially published response.
        if options.stdout && state.publication == "not_started" {
          context_write_stdout(
            context_error(state.operation, category).stringify() + "\n",
            state,
          )
        }
        if state.report_json {
          write_json_report({
            "schemaVersion": 1,
            "operation": state.operation,
            "status": "error",
            "publication": state.publication,
            "exitCode": 1,
            "error": { "category": category },
          })
        } else if !cli.context_stdio {
          @stdio.stderr.write("moon-repomix: " + category + "\n")
        }
        if state.publication == "unknown" {
          stop = true
        }
        1
      }
    }
    if !cli.context_stdio || stop {
      return code
    }
  }
}
