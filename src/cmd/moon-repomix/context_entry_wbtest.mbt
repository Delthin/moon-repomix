///|
test "portable request decoding accepts the same leading UTF-8 BOM as preset imports" {
  let request : Json = {
    "schemaVersion": 1,
    "operation": "read_code_context",
    "spec": {
      "maxTokens": 1000,
      "requests": [{ "path": "src/main.mbt", "full": true }],
    },
  }
  let encoded = @utf8.encode(request.stringify())
  assert_eq(context_parse(encoded).to_json(), request)
  assert_eq(context_parse(b"\xef\xbb\xbf" + encoded).to_json(), request)
}

///|
async test "oversized serialized response cannot publish or commit candidate session" {
  let options = @config.resolve(@config.parse_cli(["--context-stdio"]), None)
  let previous = @repomix.CodeContextSession::new(1000)
  let host : ContextHost = {
    session: Some(previous),
    latest: Some("old"),
    sequence: 7,
    prefix: "test",
  }
  let state : RunState = {
    report_json: false,
    publication: "not_started",
    operation: "read_code_context",
  }
  let pending : ContextPending = {
    response: { "text": "x".repeat(16777216) },
    session: Some(@repomix.CodeContextSession::new(500)),
    latest: Some("candidate"),
    success: true,
  }
  try context_publish(pending, options, state, host) catch {
    ResponseTooLarge => ()
    _ => fail("wrong publication failure")
  } noraise {
    _ => fail("oversized response was published")
  }
  assert_eq(state.publication, "not_started")
  assert_eq(host.latest, Some("old"))
  assert_eq(host.sequence, 7)
  assert_eq(host.session.unwrap().limit, 1000)
  assert_eq(host.session.unwrap().rounds, 0)
}
