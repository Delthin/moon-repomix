///|
test "client parameters only narrow host authority and validate every literal path" {
  let host = @repomix.options(
    ".",
    file_paths=Some(["src/a.mbt"]),
    max_files=2,
    max_total_size=100L,
    compress=true,
  )
  let (narrow, cap) = requested_options(host, 1000, {
    "filePaths": ["src/b.mbt", "src/a.mbt"],
    "maxTokens": 500,
    "compress": false,
    "style": "json",
  })
  assert_eq(narrow.file_paths, Some(["src/a.mbt"]))
  assert_eq(cap, 500)
  assert_eq(narrow.directory, host.directory)
  assert_eq(narrow.security_check, host.security_check)
  assert_eq(narrow.max_files, 2)
  assert_eq(narrow.max_total_size, 100L)
  assert_false(narrow.compress)
  assert_true(narrow.style is Json)
  let (empty, _) = requested_options(host, 1000, { "filePaths": [] })
  assert_eq(empty.file_paths, Some([]))
  let (defaults, default_cap) = requested_options(host, 1000, {})
  assert_eq(defaults.file_paths, host.file_paths)
  assert_eq(default_cap, 1000)
  let invalid_cases : Array[Json] = [
    { "root": "/" },
    { "remote": "https://example.invalid" },
    { "securityCheck": false },
    { "instructionFilePath": "anything" },
    { "maxFiles": 9999 },
    { "maxTokens": 1001 },
    { "maxTokens": 0 },
    { "maxTokens": 0.5 },
    { "maxTokens": true },
    { "style": "html" },
    { "filePaths": ["../outside"] },
    { "filePaths": ["/absolute"] },
    { "filePaths": ["a//b"] },
    { "filePaths": ["a/./b"] },
    { "filePaths": ["C:/outside"] },
    { "filePaths": ["a\\b"] },
    { "filePaths": ["a\u0000b"] },
    { "filePaths": [false] },
  ]
  for args in invalid_cases {
    let failed = try {
      ignore(requested_options(host, 1000, args))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
  assert_eq(explanation_paths({ "paths": ["src/a.mbt", "src/b.mbt"] }), [
    "src/a.mbt", "src/b.mbt",
  ])
  assert_eq(explanation_paths({ "paths": [] }), [])
  let bad_explanations : Array[Json] = [
    {},
    { "paths": false },
    { "paths": [false] },
    { "paths": ["../outside"] },
    { "paths": ["/absolute"] },
    { "paths": ["a\\b"] },
    { "paths": ["a//b"] },
    { "paths": ["a\u0000b"] },
    { "paths": ["a".repeat(4097)] },
    { "paths": Array::make(257, "src/a.mbt") },
    { "paths": [], "securityCheck": false },
    { "paths": [], "root": "/" },
    { "paths": [], "maxFiles": 9999 },
    { "paths": [], "remote": "https://example.invalid" },
  ]
  for args in bad_explanations {
    let failed = try {
      ignore(explanation_paths(args))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
  assert_true(safe_path("src/中文 file.mbt"))
  assert_true(safe_path("src/name\nline.mbt"))
  assert_false(safe_path(""))
}
