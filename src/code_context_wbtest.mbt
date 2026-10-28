///|
fn code_test_spec(
  requests : Array[Json],
  cap~ : Int32 = 100000,
  read_bytes~ : Int32 = 16777216,
) -> CodeContextSpec raise {
  CodeContextSpec::from_json({
    "maxTokens": cap,
    "maxReadBytes": read_bytes,
    "requests": requests,
  })
}

///|
async test "code context preserves complete implementations and exact inclusive ranges" {
  let root = @fs.tmpdir(prefix="moon-code-sdk-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  let source = "// unrelated padding\r\n".repeat(100) +
    "export function answer() {\r\n  return '你好';\r\n}\r\n" +
    "// unrelated ending\r\n".repeat(100)
  @fs.write_file(root + "/a.ts", source, create_mode=CreateOrTruncate)
  let runtime = Runtime::load(
    @env.current_dir().unwrap() + "/assets/tokenizer-o200k_base.tiktoken",
  )
  let base = options(
    root,
    header_text="Review implementation",
    style=Style::Xml,
  )
  let requests : Array[Json] = [{ "path": "a.ts", "symbols": ["answer"] }]
  let result = read_code_context(base, runtime, code_test_spec(requests))
  assert_eq(result.status, "complete")
  let text = result.text.unwrap()
  assert_eq(runtime.encoder.count(text), result.tokens)
  assert_eq(@utf8.encode(text).length(), result.bytes)
  assert_false(text.contains("unrelated padding"))
  let payload = @json.parse(text)
  assert_true(
    payload
    is {
      "files": [
        {
          "mode": String("ranges"),
          "fragments": [
            {
              "startLine": Number(101, ..),
              "endLine": Number(103, ..),
              "text": String(
                "export function answer() {\r\n  return '你好';\r\n}\r\n"
              ),
              ..
            },
          ],
          ..
        },
      ],
      ..
    },
  )
  let exact = read_code_context(
    base,
    runtime,
    code_test_spec(requests, cap=result.tokens),
  )
  assert_eq(exact.text, result.text)
  let short = read_code_context(
    base,
    runtime,
    code_test_spec(requests, cap=result.tokens - 1),
  )
  assert_eq(short.status, "over_budget")
  assert_eq(short.required_tokens, Some(result.tokens))
  assert_eq(short.text, None)
  assert_false(short.audit.stringify().contains("return"))
  let ranged = read_code_context(
    base,
    runtime,
    code_test_spec([
      {
        "path": "a.ts",
        "ranges": [
          { "startLine": 102, "endLine": 103 },
          { "startLine": 101, "endLine": 102 },
        ],
      },
    ]),
  )
  assert_true(
    @json.parse(ranged.text.unwrap())
    is {
      "files": [
        {
          "fragments": [
            { "startLine": Number(101, ..), "endLine": Number(103, ..), .. },
          ],
          ..
        },
      ],
      ..
    },
  )
  let outside = read_code_context(
    base,
    runtime,
    code_test_spec([
      { "path": "a.ts", "ranges": [{ "startLine": 999, "endLine": 999 }] },
    ]),
  )
  assert_eq(outside.status, "unavailable")
  assert_eq(outside.text, None)
  assert_true(outside.audit.stringify().contains("range-out-of-bounds"))
}

///|
async test "code context disambiguates and follows bounded same-file references" {
  let root = @fs.tmpdir(prefix="moon-code-symbols-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  @fs.write_file(
    root + "/a.py",
    "LIMIT = 7\n\ndef value():\n    return 0\n\ndef helper():\n    return LIMIT\n\ndef answer():\n    return helper()\n\nclass A:\n    def value(self):\n        return 1\n\nclass B:\n    def value(self):\n        return 2\n" +
    "# padding to keep selection smaller\n".repeat(100),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/tiny.js",
    "const answer = () => 42;\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(root + "/raw.zzz", "raw body\n", create_mode=CreateOrTruncate)
  @fs.write_file(
    root + "/broken.js",
    "function ( {",
    create_mode=CreateOrTruncate,
  )
  let runtime = Runtime::load(
    @env.current_dir().unwrap() + "/assets/tokenizer-o200k_base.tiktoken",
  )
  let base = options(root)
  let closure = read_code_context(
    base,
    runtime,
    code_test_spec([
      { "path": "a.py", "symbols": ["answer"], "includeDependencies": true },
    ]),
  )
  assert_eq(closure.status, "complete")
  let body = closure.text.unwrap()
  assert_true(body.contains("LIMIT = 7"))
  assert_true(body.contains("def helper"))
  assert_true(body.contains("return helper()"))
  assert_false(body.contains("return 2"))
  let ambiguous = read_code_context(
    base,
    runtime,
    code_test_spec([{ "path": "a.py", "symbols": ["value"] }]),
  )
  assert_eq(ambiguous.text, None)
  assert_true(ambiguous.audit.stringify().contains("ambiguous-symbol"))
  assert_true(ambiguous.audit.stringify().contains("B.value"))
  let qualified = read_code_context(
    base,
    runtime,
    code_test_spec([{ "path": "a.py", "symbols": ["B.value"] }]),
  )
  assert_true(qualified.text.unwrap().contains("return 2"))
  assert_false(qualified.text.unwrap().contains("return 1"))
  let missing = read_code_context(
    base,
    runtime,
    code_test_spec([{ "path": "a.py", "symbols": ["absent"] }]),
  )
  assert_eq(missing.text, None)
  assert_true(missing.audit.stringify().contains("symbol-not-found"))
  let outline = read_code_context(
    base,
    runtime,
    code_test_spec([{ "path": "a.py", "outline": true }]),
  )
  assert_true(outline.text.unwrap().contains("B.value"))
  assert_false(outline.text.unwrap().contains("return 2"))
  let tiny = read_code_context(
    base,
    runtime,
    code_test_spec([{ "path": "tiny.js", "symbols": ["answer"] }]),
  )
  assert_true(
    @json.parse(tiny.text.unwrap())
    is { "files": [{ "mode": String("full"), .. }], .. },
  )
  for path in ["raw.zzz", "broken.js"] {
    let rejected = read_code_context(
      base,
      runtime,
      code_test_spec([{ "path": path, "symbols": ["answer"] }]),
    )
    assert_eq(rejected.text, None)
    let raw = read_code_context(
      base,
      runtime,
      code_test_spec([{ "path": path, "full": true }]),
    )
    assert_eq(raw.status, "complete")
  }
}

///|
async test "code context screens whole files before exposing ranges or symbol names" {
  let root = @fs.tmpdir(prefix="moon-code-safety-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(root))
  let secret = "gh" + "p_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
  @fs.write_file(
    root + "/secret.js",
    "const key = '" + secret + "';\nfunction harmless() { return 42; }\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/ok.js",
    "function harmless() { return 42; }\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/.repomixignore",
    "ignored.js\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/ignored.js",
    "function hidden() {}\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(root + "/binary.js", b"\x00", create_mode=CreateOrTruncate)
  let runtime = Runtime::load(
    @env.current_dir().unwrap() + "/assets/tokenizer-o200k_base.tiktoken",
  )
  let base = options(root)
  for
    selector in [
      ({ "path": "secret.js", "symbols": ["harmless"] } : Json),
      { "path": "secret.js", "ranges": [{ "startLine": 2, "endLine": 2 }] },
      { "path": "secret.js", "outline": true },
    ] {
    let result = read_code_context(base, runtime, code_test_spec([selector]))
    assert_eq(result.text, None)
    assert_true(result.security is Excluded)
    assert_false(result.audit.stringify().contains(secret))
    assert_false(result.audit.stringify().contains("harmless"))
  }
  for path in ["ignored.js", "missing.js", "binary.js"] {
    let result = read_code_context(
      base,
      runtime,
      code_test_spec([{ "path": path, "full": true }]),
    )
    assert_eq(result.text, None)
  }
  let unlisted = read_code_context(
    { ..base, file_paths: Some([]), },
    runtime,
    code_test_spec([{ "path": "ok.js", "full": true }]),
  )
  assert_eq(unlisted.text, None)
  assert_true(unlisted.audit is { "attemptedReads": Number(0, ..), .. })
  let quota = read_code_context(
    base,
    runtime,
    code_test_spec([{ "path": "ok.js", "full": true }], read_bytes=10),
  )
  assert_eq(quota.text, None)
  assert_true(quota.audit is { "readBytes": String("11"), .. })
  let combined = read_code_context(
    base,
    runtime,
    code_test_spec([
      { "path": "ok.js", "full": true },
      { "path": "secret.js", "full": true },
    ]),
  )
  assert_eq(combined.text, None)
  assert_false(combined.audit.stringify().contains("return 42"))
  let disabled = read_code_context(
    { ..base, security_check: false, },
    runtime,
    code_test_spec([{ "path": "secret.js", "full": true }]),
  )
  assert_true(disabled.security is Disabled)
  assert_true(disabled.text.unwrap().contains(secret))
}
