// Copied into an external workspace consumer by context-parity-test.mbtx.
// Imports are provided by that consumer's moon.pkg; never resolve a registry SDK.

fn prop(value : Json, key : String) -> Json raise {
  guard value is Object(fields) && fields.get(key) is Some(found) else {
    fail("missing " + key)
  }
  found
}

fn text(value : Json) -> String raise {
  guard value is String(found) else { fail("expected string") }
  found
}

async fn save(root : String, name : String, value : Json) -> Unit {
  @fs.write_file(root + "/" + name + ".json", value.stringify(), create_mode=CreateNew)
}

fn security(value : @repomix.SecurityStatus) -> Json {
  { "enabled": !(value is Disabled), "status": match value {
    Passed => "passed"
    Excluded => "excluded"
    Disabled => "disabled"
  } }
}

async fn main {
  let args = @env.args()
  guard args.length() == 4 else { fail("expected FIXTURE VOCAB LOG") }
  let root = args[3]
  let runtime = @repomix.Runtime::load(args[2])
  let options = @config.resolve(@config.parse_cli([
    args[1], "--style", "json",
    "--max-files", "2000", "--max-total-size", "16777216", "--max-file-size", "2097152",
  ]), None)
  assert_true(options.security_check)
  assert_eq(options.max_file_size, 2097152)
  save(root, "sdk-capabilities", @repomix.context_capabilities())
  assert_true(@compression.definition_extensions().contains(".mbt"))
  assert_true(@compression.definition_extensions().contains(".mbti"))
  let mut session = @repomix.CodeContextSession::new(16000)
  for i in 0..<4 {
    let value = @json.parse(@fs.read_file(root + "/request-" + i.to_string() + ".json").text())
    let request = @repomix.ContextRequest::from_json(value)
    assert_eq(request.to_json(), value)
    let spec_json = request.spec_json()
    let projection : Json = match request.operation {
      Code => {
        let spec = if i == 0 {
          @repomix.CodeContextSpec::from_json(spec_json)
        } else {
          session.request(spec_json)
        }
        let plan = @repomix.read_code_context(options, runtime, spec)
        session = session.advance(plan)
        let body = plan.text.unwrap()
        let audit = plan.audit.stringify()
        assert_eq(runtime.encoder.count(body), plan.tokens)
        assert_eq(runtime.encoder.encode(body).length(), plan.tokens)
        assert_eq(@utf8.encode(body).length(), plan.bytes)
        assert_eq(prop(@json.parse(body), "audit"), plan.audit)
        {
          "status": plan.status, "body": body, "tokens": plan.tokens,
          "bytes": plan.bytes, "security": security(plan.security),
          "audit": audit, "auditTokens": runtime.encoder.count(audit),
          "auditBytes": @utf8.encode(audit).length(), "included": true,
          "session": session.to_json(),
        }
      }
      Task => {
        let plan = @repomix.plan_task_context(options, runtime, @repomix.TaskContextSpec::from_json(spec_json))
        let body = plan.text.unwrap()
        assert_eq(runtime.encoder.count(body), plan.tokens)
        assert_eq(runtime.encoder.encode(body).length(), plan.tokens)
        assert_eq(@utf8.encode(body).length(), plan.bytes)
        assert_eq(runtime.encoder.count(plan.audit_text), plan.audit_tokens)
        assert_eq(@utf8.encode(plan.audit_text).length(), plan.audit_bytes)
        {
          "status": plan.status, "body": body, "tokens": plan.tokens,
          "bytes": plan.bytes, "security": security(plan.security),
          "audit": plan.audit_text, "auditTokens": plan.audit_tokens,
          "auditBytes": plan.audit_bytes, "included": false, "session": Json::null(),
        }
      }
    }
    save(root, "sdk-" + i.to_string(), projection)
    if i == 0 {
      let before = session.to_json()
      let failed = @repomix.read_code_context(options, runtime, session.request({
        "requests": [{ "path": "src/secret.mbt", "symbols": ["harmless"] }],
      }))
      assert_eq(failed.status, "unavailable")
      assert_true(failed.security is Excluded)
      let cli_failure = @json.parse(@fs.read_file(root + "/failure-retention.json").text())
      assert_eq(prop(prop(cli_failure, "cli"), "audit"), failed.audit)
      assert_eq(session.advance(failed).to_json(), before)
      let invalid : Json = {
        "schemaVersion": 1, "operation": "read_code_context", "directory": "..",
        "spec": { "maxTokens": 1000, "requests": [{ "path": "src/main.mbt", "full": true }] },
      }
      let rejected = try { ignore(@repomix.ContextRequest::from_json(invalid)); false } catch { _ => true }
      assert_true(rejected)
      save(root, "sdk-failure", { "status": failed.status, "sessionBefore": before, "sessionAfter": session.to_json(), "invalidRejected": rejected })
    }
  }
  assert_eq(session.rounds, 3)
  assert_false(session.can_continue())
  // Recount every transport's actual complete body and audit, not per-file sums.
  for transport in ["cli", "mcp", "http"] {
    for i in 0..<4 {
      let value = @json.parse(@fs.read_file(root + "/" + transport + "-" + i.to_string() + ".json").text())
      let body = text(prop(value, "body"))
      let audit = text(prop(value, "audit"))
      assert_eq(Json(runtime.encoder.count(body)), prop(value, "tokens"))
      assert_eq(Json(runtime.encoder.encode(body).length()), prop(value, "tokens"))
      let expected = @json.parse(@fs.read_file(root + "/sdk-" + i.to_string() + ".json").text())
      assert_eq(Json(runtime.encoder.count(audit)), prop(expected, "auditTokens"))
      if prop(value, "auditTokens") is Null {} else {
        assert_eq(Json(runtime.encoder.count(audit)), prop(value, "auditTokens"))
      }
      assert_eq(Json(@utf8.encode(body).length()), prop(value, "bytes"))
      assert_eq(Json(@utf8.encode(audit).length()), prop(value, "auditBytes"))
    }
  }
  save(root, "sdk-recounts", { "state": "passed", "wholeDocuments": 16, "wholeAudits": 16 })
}
