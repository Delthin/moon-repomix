///|
priv struct CodeSession {
  run_id : String
  directory : String
  limit : Int32
  spent : Int32
  rounds : Int32
}

///|
fn code_session_json(session : CodeSession?) -> Json {
  match session {
    None => Json::null()
    Some(session) =>
      {
        "runId": session.run_id,
        "limit": session.limit,
        "spent": session.spent,
        "remaining": session.limit - session.spent,
        "rounds": session.rounds,
        "maxRounds": 3,
        "canContinue": session.rounds < 3 && session.spent < session.limit,
      }
  }
}

///|
fn check_output(value : Json) -> Unit raise {
  if @utf8.encode(value.stringify()).length() > 16777216 {
    raise PublicError(
      413, "output_too_large", "Combined response exceeds 16 MiB.",
    )
  }
}

///|
fn context_report(
  status : String,
  document : Json,
  tokens : Int32,
  bytes : Int32,
  security : @repomix.SecurityStatus,
  limit : Int32,
  required_tokens : Json,
) -> Json {
  let accepted = match document {
    { "files": Object(files), .. } => files.length()
    { "files": Array(files), .. } => files.length()
    _ => 0
  }
  {
    "status": status,
    "counts": { "acceptedFiles": accepted },
    "tokens": { "total": tokens.to_string() },
    "bytes": { "total": bytes.to_string() },
    "security": {
      "enabled": true,
      "status": if security is Excluded {
        "excluded"
      } else {
        "passed"
      },
    },
    "budget": {
      "limit": limit,
      "exceeded": status == "required_over_budget" || status == "over_budget",
    },
    "requiredTokens": required_tokens,
  }
}

///|
async fn context_options(state : State, relative : String) -> @repomix.Options {
  let directory = scoped_directory(state.options.directory, relative)
  let clean = @repomix.options(
    directory,
    style=Json,
    max_files=state.options.max_files,
    max_total_size=state.options.max_total_size,
  )
  {
    ..clean,
    stdout: true,
    security_check: true,
    max_file_size: state.options.max_file_size,
    output_file_path_style: TargetRelative,
    quiet: true,
  }
}

///|
async fn task_context(state : State, value : Json) -> Json {
  let values = fields(value, ["directory", "spec"])
  let directory = directory_field(values)
  let spec = @repomix.TaskContextSpec::from_json(
    values.get("spec").unwrap_or(Json::null()),
  ) catch {
    _ => raise PublicError(400, "invalid_request", "Invalid request.")
  }
  if state.busy {
    raise PublicError(409, "pack_busy", "A pack operation is already running.")
  }
  state.busy = true
  defer {
    state.busy = false
  }
  let (response, success) = @async.with_timeout(
    60000,
    () => {
      let options = context_options(state, directory)
      let plan = @repomix.plan_task_context(options, state.runtime, spec)
      let document = match plan.text {
        Some(text) => @json.parse(text)
        None => Json::null()
      }
      let required = match plan.audit {
        { "requiredDocumentTokens": Number(n, ..), .. } =>
          Json(n.to_int().to_string())
        _ => Json::null()
      }
      let success = plan.status == "complete" || plan.status == "with_omissions"
      let response : Json = {
        "operation": "plan_task_context",
        "directory": directory,
        "result": {
          "status": plan.status,
          "document": document,
          "serialized": match plan.text {
            Some(text) => Json(text)
            None => Json::null()
          },
          "report": context_report(
            plan.status,
            document,
            plan.tokens,
            plan.bytes,
            plan.security,
            spec.max_tokens,
            required,
          ),
        },
        "audit": {
          "document": plan.audit,
          "serialized": plan.audit_text,
          "tokens": plan.audit_tokens.to_string(),
          "bytes": plan.audit_bytes.to_string(),
          "includedInDocument": false,
        },
        "codeSession": code_session_json(
          if success {
            None
          } else {
            state.code_session
          },
        ),
      }
      check_output(response)
      (response, success)
    },
    error=PublicError(
      422, "context_timeout", "Context operation exceeded 60 seconds.",
    ),
  )
  // Commit only after timeout cleanup, complete output validation and a final
  // cancellation poll. Delivery can still fail after this server-side commit.
  @async.sleep(0)
  if success {
    state.code_session = None
  }
  response
}

///|
fn invalid_code_session() -> Unit raise {
  raise PublicError(
    409, "invalid_code_session", "Code session cannot be continued.",
  )
}

///|
async fn code_context(state : State, value : Json) -> Json {
  let values = fields(value, ["directory", "runId", "spec"])
  let directory = directory_field(values)
  if state.busy {
    raise PublicError(409, "pack_busy", "A pack operation is already running.")
  }
  state.busy = true
  defer {
    state.busy = false
  }
  let (response, next) = @async.with_timeout(
    60000,
    () => {
      let previous = match values.get("runId") {
        None => None
        Some(String(run_id)) => {
          guard state.code_session is Some(previous) &&
            previous.run_id == run_id &&
            previous.directory == directory &&
            previous.rounds < 3 &&
            previous.spent < previous.limit else {
            invalid_code_session()
            return (Json::null(), None)
          }
          Some(previous)
        }
        _ => {
          invalid()
          return (Json::null(), None)
        }
      }
      guard values.get("spec") is Some(Object(spec_fields)) else {
        invalid()
        return (Json::null(), None)
      }
      // Copy, retaining every caller field so Root rejects unknown fields and
      // invalid selector/range shapes. Only the continuation budget is supplied.
      let spec_fields = spec_fields.copy()
      if previous is Some(previous) {
        if spec_fields.contains("maxTokens") {
          invalid()
        }
        spec_fields["maxTokens"] = Json(previous.limit - previous.spent)
      }
      let spec = @repomix.CodeContextSpec::from_json(Json::object(spec_fields)) catch {
        _ => raise PublicError(400, "invalid_request", "Invalid request.")
      }
      if state.next_run == 9223372036854775807L {
        raise PublicError(409, "session_limit", "Code session limit reached.")
      }
      let options = context_options(state, directory)
      let plan = @repomix.read_code_context(options, state.runtime, spec)
      let document = match plan.text {
        Some(text) => @json.parse(text)
        None => Json::null()
      }
      let next = if plan.status == "complete" && plan.text is Some(_) {
        Some({
          run_id: "code-" + state.next_run.to_string(),
          directory,
          limit: match previous {
            Some(previous) => previous.limit
            None => spec.max_tokens
          },
          spent: plan.tokens +
          (match previous {
            Some(previous) => previous.spent
            None => 0
          }),
          rounds: 1 +
          (match previous {
            Some(previous) => previous.rounds
            None => 0
          }),
        })
      } else {
        state.code_session
      }
      let audit_text = plan.audit.stringify()
      let response : Json = {
        "operation": "read_code_context",
        "directory": directory,
        "result": {
          "status": plan.status,
          "document": document,
          "serialized": match plan.text {
            Some(text) => Json(text)
            None => Json::null()
          },
          "report": context_report(
            plan.status,
            document,
            plan.tokens,
            plan.bytes,
            plan.security,
            spec.max_tokens,
            match plan.required_tokens {
              Some(n) => Json(n.to_string())
              None => Json::null()
            },
          ),
        },
        "audit": {
          "document": plan.audit,
          "serialized": audit_text,
          "tokens": state.runtime.encoder.count(audit_text).to_string(),
          "bytes": @utf8.encode(audit_text).length().to_string(),
          "includedInDocument": true,
        },
        "codeSession": code_session_json(next),
      }
      check_output(response)
      (
        response,
        if plan.status == "complete" && plan.text is Some(_) {
          next
        } else {
          None
        },
      )
    },
    error=PublicError(
      422, "context_timeout", "Context operation exceeded 60 seconds.",
    ),
  )
  @async.sleep(0)
  if next is Some(_) {
    state.code_session = next
    state.next_run += 1L
  }
  response
}
