///|
async fn context_test_state(root : String) -> State {
  let resource = @env.current_dir().unwrap() +
    "/assets/tokenizer-o200k_base.tiktoken"
  {
    options: @repomix.options(canonical_root(root), style=Json),
    runtime: @repomix.Runtime::load(resource),
    resource,
    port: 8765,
    busy: false,
    code_session: None,
    next_run: 1L,
  }
}

///|
fn test_code_request(cap : Int32, path~ : String = "sample.txt") -> Json {
  {
    "directory": ".",
    "spec": { "maxTokens": cap, "requests": [{ "path": path, "full": true }] },
  }
}

///|
fn test_continue(run_id : String, directory~ : String = ".") -> Json {
  {
    "directory": directory,
    "runId": run_id,
    "spec": { "requests": [{ "path": "sample.txt", "full": true }] },
  }
}

///|
fn test_task_request(cap : Int32, optional~ : Bool = false) -> Json {
  {
    "directory": ".",
    "spec": {
      "maxTokens": cap,
      "tasks": [
        {
          "id": "review",
          "required": [{ "path": "sample.txt", "mode": "full" }],
          "optional": if optional {
            [{ "path": "missing.txt", "mode": "either", "priority": 90 }]
          } else {
            []
          },
        },
      ],
    },
  }
}

///|
fn test_result(value : Json) -> Map[String, Json] raise {
  guard value is { "result": Object(result), .. } else {
    fail("missing result")
  }
  result
}

///|
fn assert_exact_context(
  value : Json,
  state : State,
  included : Bool,
) -> Unit raise {
  let result = test_result(value)
  guard result.get("serialized") is Some(String(text)) &&
    result.get("document") is Some(document) &&
    value
    is {
      "audit": {
        "document": audit,
        "serialized": String(audit_text),
        "tokens": String(audit_tokens),
        "bytes": String(audit_bytes),
        "includedInDocument": embedded,
        ..
      },
      ..
    } else {
    fail("missing complete context")
  }
  assert_eq(@json.parse(text), document)
  assert_eq(@json.parse(audit_text), audit)
  assert_eq(audit_tokens, state.runtime.encoder.count(audit_text).to_string())
  assert_eq(audit_bytes, @utf8.encode(audit_text).length().to_string())
  assert_eq(embedded, Json(included))
  assert_true(
    result.get("report")
    is Some(
      {
        "tokens": { "total": String(tokens), .. },
        "bytes": { "total": String(bytes), .. },
        "security": { "enabled": True, "status": String("passed"), .. },
        ..
      }
    ) &&
    tokens == state.runtime.encoder.count(text).to_string() &&
    bytes == @utf8.encode(text).length().to_string(),
  )
  if included {
    assert_true(
      document is { "audit": embedded_audit, .. } && embedded_audit == audit,
    )
  }
}

///|
async test "task DTO uses real Root body and independent audit; failure preserves code session" {
  let root = @fs.tmpdir(prefix="webui-task-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  let source = "synthetic implementation\r\n你好\n"
  @fs.write_file(root + "/sample.txt", source, create_mode=CreateNew)
  let state = context_test_state(root)
  ignore(code_context(state, test_code_request(10000)))
  let old = code_session_json(state.code_session)
  let failed = task_context(state, test_task_request(1))
  assert_true(
    test_result(failed).get("status") is Some(String("required_over_budget")),
  )
  assert_true(test_result(failed).get("document") is Some(Null))
  assert_true(test_result(failed).get("serialized") is Some(Null))
  assert_true(
    test_result(failed).get("report")
    is Some(
      {
        "tokens": { "total": String("0"), .. },
        "bytes": { "total": String("0"), .. },
        "requiredTokens": String(required),
        "budget": { "limit": Number(1, ..), "exceeded": True, .. },
        ..
      }
    ) &&
    required != "0",
  )
  assert_eq(code_session_json(state.code_session), old)
  assert_true(failed is { "codeSession": saved, .. } && saved == old)
  @fs.remove(root + "/sample.txt")
  let absent = task_context(state, test_task_request(10000))
  assert_true(
    test_result(absent).get("status") is Some(String("required_unavailable")),
  )
  assert_eq(code_session_json(state.code_session), old)
  @fs.write_file(root + "/sample.txt", source, create_mode=CreateNew)
  let success = task_context(state, test_task_request(10000, optional=true))
  assert_exact_context(success, state, false)
  assert_true(
    test_result(success).get("status") is Some(String("with_omissions")),
  )
  assert_true(
    test_result(success).get("document")
    is Some({ "files": { "sample.txt": String(body), .. }, .. }) &&
    body == source,
  )
  assert_eq(code_session_json(state.code_session), Json::null())
  assert_true(success is { "codeSession": Null, .. })
  assert_true(
    session(state)
    is {
      "capabilities": Array(capabilities),
      "codeMaxRounds": Number(3, ..),
      ..
    } &&
    capabilities.contains(Json("code-context")),
  )
  ignore(code_context(state, test_code_request(10000)))
  let complete = task_context(state, test_task_request(10000))
  assert_true(test_result(complete).get("status") is Some(String("complete")))
  assert_true(state.code_session is None)
}

///|
async test "code session accumulates only embedded body tokens, rotates ids and allows three successes" {
  let root = @fs.tmpdir(prefix="webui-code-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  @fs.mkdir(root + "/child")
  @fs.write_file(
    root + "/sample.txt",
    "one\r\n二\nthree\n",
    create_mode=CreateNew,
  )
  let state = context_test_state(root)
  let rejected_first = code_context(state, test_code_request(1))
  assert_true(rejected_first is { "codeSession": Null, .. })
  assert_true(state.code_session is None)
  assert_eq(state.next_run, 1L)
  let first = code_context(state, test_code_request(10000))
  assert_exact_context(first, state, true)
  let initial = state.code_session.unwrap()
  let text = match test_result(first).get("serialized") {
    Some(String(text)) => text
    _ => fail("text")
  }
  assert_eq(initial.accounting.spent, state.runtime.encoder.count(text))
  assert_eq(initial.accounting.rounds, 1)
  assert_true(
    test_result(first).get("report")
    is Some({ "counts": { "acceptedFiles": Number(1, ..), .. }, .. }),
  )
  let saved = code_session_json(state.code_session)
  // An explicit new first round that fails must not replace the old session.
  let tiny = code_context(state, test_code_request(1))
  assert_true(test_result(tiny).get("status") is Some(String("over_budget")))
  assert_true(test_result(tiny).get("serialized") is Some(Null))
  assert_true(
    test_result(tiny).get("report")
    is Some({ "requiredTokens": String(required), .. }) &&
    required == initial.accounting.spent.to_string(),
  )
  assert_eq(code_session_json(state.code_session), saved)
  for
    request in [
      test_continue("stale"),
      test_continue(initial.run_id, directory="child"),
    ] {
    try code_context(state, request) catch {
      PublicError(409, "invalid_code_session", _) => ()
      _ => fail("expected safe session conflict")
    } noraise {
      _ => fail("expected conflict")
    }
    assert_eq(code_session_json(state.code_session), saved)
  }
  let missing = code_context(state, {
    "directory": ".",
    "runId": initial.run_id,
    "spec": { "requests": [{ "path": "missing.txt", "full": true }] },
  })
  assert_true(test_result(missing).get("status") is Some(String("unavailable")))
  assert_eq(code_session_json(state.code_session), saved)
  let second = code_context(state, test_continue(initial.run_id))
  assert_exact_context(second, state, true)
  let middle = state.code_session.unwrap()
  assert_eq(middle.accounting.spent, initial.accounting.spent * 2)
  assert_eq(middle.accounting.rounds, 2)
  assert_true(middle.run_id != initial.run_id)
  try code_context(state, test_continue(initial.run_id)) catch {
    PublicError(409, "invalid_code_session", _) => ()
    _ => fail("wrong stale-id error")
  } noraise {
    _ => fail("old id accepted")
  }
  let third = code_context(state, test_continue(middle.run_id))
  let final_session = state.code_session.unwrap()
  assert_eq(final_session.accounting.spent, initial.accounting.spent * 3)
  assert_eq(final_session.accounting.rounds, 3)
  assert_true(
    third
    is {
      "codeSession": {
        "limit": Number(10000, ..),
        "spent": Number(spent, ..),
        "remaining": Number(remaining, ..),
        "canContinue": False,
        ..
      },
      ..
    } &&
    spent + remaining == 10000,
  )
  try code_context(state, test_continue(final_session.run_id)) catch {
    PublicError(409, "invalid_code_session", _) => ()
    _ => fail("wrong round-limit error")
  } noraise {
    _ => fail("fourth round accepted")
  }
  // A valid continuation whose body does not fit must not consume a round.
  ignore(
    code_context(state, test_code_request(initial.accounting.spent * 2 - 1)),
  )
  let before_over_budget = code_session_json(state.code_session)
  let before_run = state.next_run
  let over_budget = code_context(
    state,
    test_continue(state.code_session.unwrap().run_id),
  )
  assert_true(
    test_result(over_budget).get("status") is Some(String("over_budget")),
  )
  assert_true(
    over_budget is { "codeSession": saved, .. } && saved == before_over_budget,
  )
  assert_eq(code_session_json(state.code_session), before_over_budget)
  assert_eq(state.next_run, before_run)
  // A new session may use a smaller limit; exact exhaustion forbids continuing.
  let exact = code_context(state, test_code_request(initial.accounting.spent))
  assert_true(
    exact
    is {
      "codeSession": {
        "remaining": Number(0, ..),
        "rounds": Number(1, ..),
        "canContinue": False,
        ..
      },
      ..
    },
  )
  try
    code_context(state, test_continue(state.code_session.unwrap().run_id))
  catch {
    PublicError(409, "invalid_code_session", _) => ()
    _ => fail("wrong exhausted-budget error")
  } noraise {
    _ => fail("exhausted budget accepted")
  }
}

///|
async test "context HTTP schema delegates strict specs to Root and inherits only resource ceilings" {
  let root = @fs.tmpdir(prefix="webui-context-scope-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  @fs.mkdir(root + "/child")
  @fs.mkdir(root + "/outside")
  @fs.symlink(target=root + "/outside", root + "/child/link")
  defer @async.protect_from_cancel(() => {
    remove_fixture_directory_link(root + "/child/link")
  })
  let secret = "gh" + "p_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
  @fs.write_file(
    root + "/child/secret.js",
    "const token = '" + secret + "';\nfunction safe() { return 7; }\n",
    create_mode=CreateNew,
  )
  @fs.write_file(
    root + "/child/sample.txt",
    "scoped body\n",
    create_mode=CreateNew,
  )
  let base = context_test_state(root)
  let state = {
    ..base,
    options: {
      ..base.options,
      security_check: false,
      header_text: "unused host header",
      include_patterns: ["not-selected"],
      max_total_size: 20L,
    },
  }
  let read = code_context(state, {
    "directory": "child",
    "spec": {
      "maxTokens": 10000,
      "requests": [
        { "path": "sample.txt", "ranges": [{ "startLine": 1, "endLine": 1 }] },
      ],
    },
  })
  assert_exact_context(read, state, true)
  assert_false(read.stringify().contains("unused host header"))
  let old = code_session_json(state.code_session)
  let denied = code_context(state, {
    "directory": "child",
    "spec": {
      "maxTokens": 10000,
      "requests": [
        { "path": "secret.js", "ranges": [{ "startLine": 2, "endLine": 2 }] },
      ],
    },
  })
  assert_true(test_result(denied).get("document") is Some(Null))
  assert_false(denied.stringify().contains(secret))
  assert_eq(code_session_json(state.code_session), old)
  // A fresh state with normal read allowance proves security, not just quota,
  // excludes an otherwise valid requested line after whole-file scanning.
  let screened = code_context(base, {
    "directory": "child",
    "spec": {
      "maxTokens": 10000,
      "requests": [{ "path": "secret.js", "outline": true }],
    },
  })
  assert_true(
    test_result(screened).get("report")
    is Some(
      { "security": { "enabled": True, "status": String("excluded"), .. }, .. }
    ),
  )
  assert_false(screened.stringify().contains(secret))
  let screened_task = task_context(base, {
    "directory": "child",
    "spec": {
      "maxTokens": 10000,
      "tasks": [
        {
          "id": "review",
          "required": [{ "path": "secret.js", "mode": "full" }],
        },
      ],
    },
  })
  assert_true(
    test_result(screened_task).get("status")
    is Some(String("required_unavailable")),
  )
  assert_true(
    test_result(screened_task).get("report")
    is Some(
      { "security": { "enabled": True, "status": String("excluded"), .. }, .. }
    ),
  )
  assert_false(screened_task.stringify().contains(secret))
  let scoped_task = task_context(base, {
    "directory": "child",
    "spec": {
      "maxTokens": 10000,
      "tasks": [
        {
          "id": "review",
          "required": [{ "path": "sample.txt", "mode": "full" }],
        },
      ],
    },
  })
  assert_true(
    test_result(scoped_task).get("document")
    is Some({ "files": { "sample.txt": String("scoped body\n"), .. }, .. }),
  )
  for directory in ["../outside", "child/link"] {
    try
      code_context(state, {
        "directory": directory,
        "spec": {
          "maxTokens": 10000,
          "requests": [{ "path": "sample.txt", "full": true }],
        },
      })
    catch {
      PublicError(code, _, message) => {
        assert_true(code == 400 || code == 403)
        assert_false(message.contains(root))
      }
      _ => fail("unsafe scope error")
    } noraise {
      _ => fail("scope escape accepted")
    }
  }
  for
    spec in [
      (
        { "maxTokens": 0, "requests": [{ "path": "sample.txt", "full": true }] } :
        Json),
      {
        "maxTokens": 10000,
        "unknown": 1,
        "requests": [{ "path": "sample.txt", "full": true }],
      },
      {
        "maxTokens": 10000,
        "requests": [{ "path": "../sample.txt", "full": true }],
      },
      {
        "maxTokens": 10000,
        "requests": [
          { "path": "sample.txt", "ranges": [{ "startLine": 2, "endLine": 1 }] },
        ],
      },
    ] {
    try code_context(state, { "directory": ".", "spec": spec }) catch {
      PublicError(400, "invalid_request", "Invalid request.") => ()
      _ => fail("unsafe spec error")
    } noraise {
      _ => fail("invalid spec accepted")
    }
  }
  try
    code_context(state, {
      "directory": "child",
      "runId": state.code_session.unwrap().run_id,
      "spec": {
        "maxTokens": 10000,
        "requests": [{ "path": "sample.txt", "full": true }],
      },
    })
  catch {
    PublicError(400, "invalid_request", _) => ()
    _ => fail("wrong continuation-budget error")
  } noraise {
    _ => fail("continuation changed budget")
  }
  try
    task_context(state, {
      "directory": ".",
      "spec": {
        "maxTokens": 100,
        "tasks": [
          {
            "id": "a",
            "required": [{ "path": "sample.txt", "mode": "either" }],
          },
        ],
      },
    })
  catch {
    PublicError(400, "invalid_request", _) => ()
    _ => fail("wrong task schema error")
  } noraise {
    _ => fail("invalid required mode accepted")
  }
  assert_eq(code_session_json(state.code_session), old)
  assert_false(state.busy)
}

///|
async test "context and pack share busy gate; cancellation and successful pack preserve commit rules" {
  let root = @fs.tmpdir(prefix="webui-context-cancel-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  @fs.write_file(root + "/sample.txt", "sample source\n", create_mode=CreateNew)
  let state = context_test_state(root)
  ignore(code_context(state, test_code_request(10000)))
  let old = code_session_json(state.code_session)
  for operation in ["code", "task", "pack"] {
    @async.with_task_group(group => {
      let running = group.spawn(
        () => {
          match operation {
            "task" => task_context(state, test_task_request(10000))
            "code" => code_context(state, test_code_request(10000))
            _ =>
              build(state, {
                directory: ".",
                profile: "raw",
                budget: 10000,
                includes: [],
                keep_full: [],
              })
          }
        },
        allow_failure=true,
      )
      @async.pause()
      assert_true(state.busy)
      for blocked in [false, true] {
        try {
          if blocked {
            task_context(state, test_task_request(10000))
          } else {
            code_context(state, test_code_request(10000))
          }
        } catch {
          PublicError(409, "pack_busy", _) => ()
          _ => fail("wrong busy error")
        } noraise {
          _ => fail("concurrent context accepted")
        }
      }
      try
        build(state, {
          directory: ".",
          profile: "raw",
          budget: 10000,
          includes: [],
          keep_full: [],
        })
      catch {
        PublicError(409, "pack_busy", _) => ()
        _ => fail("wrong pack busy error")
      } noraise {
        _ => fail("concurrent pack accepted")
      }
      running.cancel()
      try running.wait() catch {
        err => assert_true(@async.is_cancellation_error(err))
      } noraise {
        _ => fail("cancellation swallowed")
      }
    })
    assert_eq(code_session_json(state.code_session), old)
    assert_false(state.busy)
  }
  let run = state.code_session.unwrap().run_id
  let packed = build(state, {
    directory: ".",
    profile: "raw",
    budget: 10000,
    includes: [],
    keep_full: [],
  })
  assert_true(
    packed
    is {
      "profile": String("raw"),
      "baseline": { "serialized": String(_), .. },
      "result": { "serialized": String(_), .. },
      ..
    },
  )
  assert_true(state.code_session is None)
  try code_context(state, test_continue(run)) catch {
    PublicError(409, "invalid_code_session", _) => ()
    _ => fail("wrong pack-invalidated session error")
  } noraise {
    _ => fail("pack did not invalidate old id")
  }
}

///|
async test "whole context response output ceiling rejects a real Root body without spending session" {
  let root = @fs.tmpdir(prefix="webui-context-output-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  @fs.write_file(root + "/sample.txt", "small source\n", create_mode=CreateNew)
  let state = context_test_state(root)
  ignore(code_context(state, test_code_request(10000)))
  let old = code_session_json(state.code_session)
  // Each file fits the host's per-file ceiling, and Root's body itself fits
  // 16 MiB. Duplicating parsed + serialized escaped JSON crosses the HTTP cap.
  for path in ["large-a.txt", "large-b.txt"] {
    @fs.write_file(
      root + "/" + path,
      "\"".repeat(1500000),
      create_mode=CreateNew,
    )
    assert_eq(@fs.read_file(root + "/" + path).text().length(), 1500000)
  }
  try
    code_context(state, {
      "directory": ".",
      "spec": {
        "maxTokens": 2147483647,
        "requests": [
          { "path": "large-a.txt", "full": true },
          { "path": "large-b.txt", "full": true },
        ],
      },
    })
  catch {
    PublicError(413, "output_too_large", _) => ()
    _ => fail("wrong output-limit error")
  } noraise {
    response => {
      let bytes = @utf8.encode(response.stringify()).length()
      let report = test_result(response).get("report").unwrap_or(Json::null())
      let audit = match response {
        { "audit": { "document": audit, .. }, .. } => audit
        _ => Json::null()
      }
      fail(
        "oversized envelope accepted: bytes=" +
        bytes.to_string() +
        "; report=" +
        report.stringify() +
        "; audit=" +
        audit.stringify(),
      )
    }
  }
  assert_eq(code_session_json(state.code_session), old)
  assert_false(state.busy)
  assert_eq(state.next_run, 2L)
}
