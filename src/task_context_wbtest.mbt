///|
fn task_test_spec(
  cap : Int32,
  required : Array[Json],
  optional : Array[Json],
  attempts~ : Int32 = 256,
  read_bytes~ : Int32 = 16777216,
) -> TaskContextSpec raise {
  TaskContextSpec::from_json({
    "maxTokens": cap,
    "maxAttempts": attempts,
    "maxReadBytes": read_bytes,
    "tasks": [{ "id": "review", "required": required, "optional": optional }],
  })
}

///|
fn task_test_paths(plan : TaskContextPlan) -> Map[String, Json] {
  guard plan.audit is { "paths": Array(paths), .. } else {
    abort("missing audit paths")
  }
  let result : Map[String, Json] = Map([])
  for entry in paths {
    if entry is { "path": String(path), .. } {
      result[path] = entry
    }
  }
  result
}

///|
test "task specification is strict, stable and merges stronger modes" {
  let spec = TaskContextSpec::from_json({
    "maxTokens": 1000,
    "tasks": [
      {
        "id": "b",
        "optional": [{ "path": "shared.ts", "mode": "full", "priority": 30 }],
      },
      {
        "id": "a",
        "required": [{ "path": "shared.ts", "mode": "skeleton" }],
        "optional": [
          { "path": "z.ts", "mode": "either", "priority": 50 },
          { "path": "a.ts", "mode": "full", "priority": 50 },
        ],
      },
    ],
  })
  let parsed = parse_task_description(@json.parse(spec.source))
  assert_eq(parsed.tasks.map(task => task.id), ["a", "b"])
  assert_eq(parsed.candidates.map(candidate => candidate.path), [
    "shared.ts", "a.ts", "z.ts",
  ])
  assert_true(parsed.candidates[0].required)
  assert_eq(parsed.candidates[0].mode, "full")
  let invalid_values : Array[Json] = [
    { "maxTokens": 0, "tasks": [{ "id": "a" }] },
    { "maxTokens": 1.5, "tasks": [{ "id": "a" }] },
    { "maxTokens": 1, "tasks": [] },
    { "maxTokens": 1, "tasks": [{ "id": "a" }, { "id": "a" }] },
    {
      "maxTokens": 1,
      "tasks": [
        { "id": "a", "required": [{ "path": "a.ts", "mode": "either" }] },
      ],
    },
    {
      "maxTokens": 1,
      "tasks": [
        {
          "id": "a",
          "optional": [{ "path": "a.ts", "mode": "full", "priority": 101 }],
        },
      ],
    },
    { "maxTokens": 1, "maxAttempts": 1, "tasks": [{ "id": "a" }] },
    { "maxTokens": 1, "maxReadBytes": 16777217, "tasks": [{ "id": "a" }] },
    { "maxTokens": 1, "securityCheck": false, "tasks": [{ "id": "a" }] },
  ]
  for value in invalid_values {
    try TaskContextSpec::from_json(value) catch {
      InvalidTaskSpec => ()
    } noraise {
      _ => fail("invalid spec accepted")
    }
  }
  for path in ["", "/a", "../a", "a//b", "a/./b", "a\\b", "C:a", "a\u{0}"] {
    try task_test_spec(1000, [{ "path": path, "mode": "full" }], []) catch {
      InvalidTaskSpec => ()
      err => raise err
    } noraise {
      _ => fail("invalid path accepted")
    }
  }
  let tasks : Array[Json] = Array::makei(17, i => {
    ({ "id": i.to_string() } : Json)
  })
  try TaskContextSpec::from_json({ "maxTokens": 1, "tasks": tasks }) catch {
    InvalidTaskSpec => ()
  } noraise {
    _ => fail("too many tasks accepted")
  }
  let entries : Array[Json] = Array::makei(129, i => {
    ({ "path": i.to_string(), "mode": "full" } : Json)
  })
  try task_test_spec(1000, [], entries) catch {
    InvalidTaskSpec => ()
    err => raise err
  } noraise {
    _ => fail("too many candidates accepted")
  }
}

///|
test "task description bounds merged paths and normalized serialized bytes" {
  let required : Array[Json] = Array::makei(128, i => {
    ({ "path": i.to_string(), "mode": "full" } : Json)
  })
  try
    task_test_spec(1000, required, [{ "path": "extra", "mode": "full" }])
  catch {
    InvalidTaskSpec => ()
    err => raise err
  } noraise {
    _ => fail("too many merged paths accepted")
  }
  let repeated : Array[Json] = Array::makei(128, _ => {
    ({ "path": "a".repeat(4000), "mode": "full" } : Json)
  })
  let tasks : Array[Json] = Array::makei(3, i => {
    ({ "id": i.to_string(), "required": repeated } : Json)
  })
  try TaskContextSpec::from_json({ "maxTokens": 1000, "tasks": tasks }) catch {
    InvalidTaskSpec => ()
  } noraise {
    _ => fail("oversized task description accepted")
  }
}

///|
test "task budget measures whole documents and reserves final measurement without monotonic assumptions" {
  let choice = fn(path : String) -> TaskChosen {
    {
      file: { path, text: "body", },
      mode: "full",
      transform: None,
      fallback: None,
    }
  }
  // Adding a file can reduce a synthetic whole-document count. No additive
  // estimate or binary-search monotonicity assumption is allowed here.
  let budget = TaskBudget::new(
    10,
    4,
    [],
    choices => choices.map(c => c.file.path).join(","),
    text => if text == "a" { 11 } else if text == "b" { 3 } else { 9 },
  )
  assert_false(budget.try_add(choice("a")))
  assert_true(budget.try_add(choice("b")))
  assert_false(budget.can_try())
  assert_eq(budget.selected.map(c => c.file.path), ["b"])
  assert_true(budget.finish())
  assert_eq((budget.tokens, budget.attempts), (3, 4))
}

///|
async test "task context exact output caps across formats and lazy bounded reads" {
  let root = @fs.tmpdir(prefix="moon-task-sdk-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  @fs.mkdir(root + "/src")
  let body = "export function answer() {\r\n" +
    "  const row = { message: 'retain signature, omit implementation', value: 42 };\r\n".repeat(
      50,
    ) +
    "  return row;\r\n}\r\n"
  @fs.write_file(root + "/src/a.ts", body, create_mode=CreateOrTruncate)
  @fs.write_file(
    root + "/src/b.ts",
    "export const other = 17;\n",
    create_mode=CreateOrTruncate,
  )
  let runtime = Runtime::load(
    @env.current_dir().unwrap() + "/assets/tokenizer-o200k_base.tiktoken",
  )
  let req : Array[Json] = [{ "path": "src/a.ts", "mode": "full" }]
  for style in [Style::Json, Style::Xml, Style::Markdown, Style::Plain] {
    let base = options(
      root,
      style~,
      header_text="Review this code",
      full_metadata=true,
      show_line_numbers=true,
    )
    let full = plan_task_context(base, runtime, task_test_spec(100000, req, []))
    assert_eq(full.status, "complete")
    assert_eq(runtime.encoder.count(full.text.unwrap()), full.tokens)
    assert_eq(@utf8.encode(full.text.unwrap()).length(), full.bytes)
    assert_eq(runtime.encoder.count(full.audit_text), full.audit_tokens)
    assert_eq(@utf8.encode(full.audit_text).length(), full.audit_bytes)
    assert_eq(full.audit.stringify(), full.audit_text)
    assert_false(full.audit_text.contains("omit implementation"))
    assert_false(full.audit_text.contains(root))
    let exact = plan_task_context(
      base,
      runtime,
      task_test_spec(full.tokens, req, []),
    )
    assert_eq(exact.text, full.text)
    let fail_plan = plan_task_context(
      base,
      runtime,
      task_test_spec(full.tokens - 1, req, []),
    )
    assert_eq(fail_plan.status, "required_over_budget")
    assert_eq(fail_plan.text, None)
    assert_eq(fail_plan.tokens, 0)
    let skeleton = plan_task_context(
      base,
      runtime,
      task_test_spec(100000, [{ "path": "src/a.ts", "mode": "skeleton" }], []),
    )
    assert_true(
      task_test_paths(skeleton)["src/a.ts"]
      is { "mode": String("skeleton"), .. },
    )
    assert_true(skeleton.tokens < full.tokens)
    let either = plan_task_context(
      base,
      runtime,
      task_test_spec(skeleton.tokens, [], [
        { "path": "src/a.ts", "mode": "either" },
      ]),
    )
    assert_eq(either.status, "complete")
    assert_eq(either.text, skeleton.text)
    assert_true(
      either.audit
      is { "attempts": Number(4, ..), "attemptedReads": Number(1, ..), .. },
    )
    let kept = plan_task_context(
      { ..base, keep_full_patterns: ["src/**"], },
      runtime,
      task_test_spec(100000, [{ "path": "src/a.ts", "mode": "skeleton" }], []),
    )
    assert_eq(kept.text, full.text)
    assert_true(
      task_test_paths(kept)["src/a.ts"]
      is { "mode": String("full"), "fallback": String("kept-full"), .. },
    )
    let bounded = plan_task_context(
      base,
      runtime,
      task_test_spec(
        100000,
        req,
        [{ "path": "src/b.ts", "mode": "full" }],
        attempts=2,
      ),
    )
    assert_eq(bounded.status, "with_omissions")
    assert_true(
      bounded.audit
      is { "attempts": Number(2, ..), "attemptedReads": Number(1, ..), .. },
    )
    assert_true(
      task_test_paths(bounded)["src/b.ts"]
      is {
        "scanned": False,
        "reason": String("not_evaluated_attempt_limit"),
        ..
      },
    )
  }
  let base = options(root, style=Style::Json)
  let quota = plan_task_context(
    base,
    runtime,
    task_test_spec(
      100000,
      [],
      [
        { "path": "src/a.ts", "mode": "full", "priority": 1 },
        { "path": "src/b.ts", "mode": "full" },
      ],
      read_bytes=10,
    ),
  )
  assert_true(
    quota.audit
    is { "readBytes": String("11"), "attemptedReads": Number(1, ..), .. },
  )
  assert_true(
    task_test_paths(quota)["src/b.ts"]
    is { "scanned": False, "reason": String("not_evaluated_read_limit"), .. },
  )
  let required_quota = plan_task_context(
    base,
    runtime,
    task_test_spec(100000, req, [], read_bytes=10),
  )
  assert_eq(required_quota.status, "required_unavailable")
  assert_eq(required_quota.text, None)
  let shared = plan_task_context(
    base,
    runtime,
    TaskContextSpec::from_json({
      "maxTokens": 100000,
      "tasks": [{ "id": "a", "required": req }, { "id": "b", "required": req }],
    }),
  )
  assert_true(
    shared.audit
    is { "attemptedReads": Number(1, ..), "selectedCount": Number(1, ..), .. },
  )
}

///|
async test "task context preserves host selection security and full fallback" {
  let root = @fs.tmpdir(prefix="moon-task-security-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  @fs.mkdir(root + "/src")
  let secret = "gh" + "p_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
  @fs.write_file(
    root + "/src/secret.ts",
    "export const key = '" + secret + "';",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/src/ignored.ts",
    "ignored",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/.repomixignore",
    "src/ignored.ts\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/src/raw.zzz",
    "unchanged unsupported language\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(root + "/src/binary.ts", b"\x00", create_mode=CreateOrTruncate)
  @fs.write_file(
    root + "/src/invalid.ts",
    b"\xff",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/src/xml.ts",
    "hello \u{ffff}",
    create_mode=CreateOrTruncate,
  )
  let runtime = Runtime::load(
    @env.current_dir().unwrap() + "/assets/tokenizer-o200k_base.tiktoken",
  )
  let base = options(root, style=Style::Json)
  let optional : Array[Json] = [
    "secret.ts", "ignored.ts", "raw.zzz", "binary.ts", "invalid.ts", "missing.ts",
  ].map(name => ({ "path": "src/" + name, "mode": "skeleton" } : Json))
  let plan = plan_task_context(
    base,
    runtime,
    task_test_spec(100000, [], optional),
  )
  assert_eq(plan.status, "with_omissions")
  assert_true(plan.security is Excluded)
  assert_false(plan.text.unwrap().contains(secret))
  assert_false(plan.audit_text.contains(secret))
  let paths = task_test_paths(plan)
  assert_true(
    paths["src/secret.ts"]
    is { "scanned": True, "reason": String("SecurityFinding"), .. },
  )
  assert_true(
    paths["src/ignored.ts"] is { "scanned": False, "selected": False, .. },
  )
  assert_true(
    paths["src/raw.zzz"]
    is { "mode": String("full"), "selected": True, "fallback": String(_), .. },
  )
  assert_true(paths["src/binary.ts"] is { "reason": String("Binary"), .. })
  assert_true(
    paths["src/invalid.ts"] is { "reason": String("InvalidUtf8"), .. },
  )
  assert_true(
    paths["src/missing.ts"] is { "reason": String("MissingFile"), .. },
  )
  let absent = plan_task_context(
    base,
    runtime,
    task_test_spec(
      100000,
      [{ "path": "src/ignored.ts", "mode": "full" }],
      optional,
    ),
  )
  assert_eq(absent.status, "required_unavailable")
  assert_true(absent.audit is { "attemptedReads": Number(0, ..), .. })
  let denied = plan_task_context(
    { ..base, file_paths: Some([]), },
    runtime,
    task_test_spec(100000, [], optional),
  )
  assert_true(denied.audit is { "attemptedReads": Number(0, ..), .. })
  assert_true(
    task_test_paths(denied)["src/raw.zzz"]
    is { "reason": String("NotListed"), .. },
  )
  let xml = plan_task_context(
    { ..base, style: Style::Xml, },
    runtime,
    task_test_spec(100000, [{ "path": "src/xml.ts", "mode": "full" }], []),
  )
  assert_eq(xml.status, "required_unavailable")
  let disabled = plan_task_context(
    { ..base, security_check: false, },
    runtime,
    task_test_spec(100000, [{ "path": "src/secret.ts", "mode": "full" }], []),
  )
  assert_true(disabled.security is Disabled)
  assert_true(disabled.text.unwrap().contains(secret))
  for
    invalid in [
      { ..base, include_files: false, },
      { ..base, include_logs: true, },
    ] {
    try
      plan_task_context(invalid, runtime, task_test_spec(1000, [], []))
    catch {
      ConfigurationError => ()
      err => raise err
    } noraise {
      _ => fail("incompatible host options accepted")
    }
  }
}
