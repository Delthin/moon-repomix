///|
async test "requested-path explanations share source screening, quotas and safe projections" {
  let temp = @fs.tmpdir(prefix="moon-explain-sdk-")
  defer @fs.rmdir(temp, recursive=true)
  let root = temp + "/repo"
  @fs.mkdir(temp + "/.git", recursive=true)
  @fs.mkdir(root + "/src", recursive=true)
  @fs.write_file(
    temp + "/.gitignore",
    "repo/src/ancestor-*.ts\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/.repomixignore",
    "src/ignored*.ts\n",
    create_mode=CreateOrTruncate,
  )
  let body = b"\xef\xbb\xbfexport const answer = 42;\r\n"
  @fs.write_file(root + "/src/a.ts", body, create_mode=CreateOrTruncate)
  @fs.write_file(root + "/src/binary.ts", b"\x00", create_mode=CreateOrTruncate)
  @fs.write_file(
    root + "/src/invalid.ts",
    b"\xff",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/src/ignored.ts",
    "not opened",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/src/ancestor-hidden.ts",
    "not opened",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    root + "/src/xml.ts",
    "export const x = 1;\n// \u{ffff}\n",
    create_mode=CreateOrTruncate,
  )
  let secret = "gh" + "p_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
  @fs.write_file(root + "/src/secret.ts", secret, create_mode=CreateOrTruncate)
  let output = root + "/context.json"
  @fs.write_file(output, "OLD OUTPUT", create_mode=CreateOrTruncate)
  let options = {
    ..options(root, style=Style::Json),
    output,
    tokenizer_path: Some(temp + "/missing-tokenizer"),
    instruction_file_path: Some(temp + "/missing-instructions"),
  }
  let report = explain_selection(options, [
    "src/secret.ts", "src/a.ts", "src/binary.ts", "src/invalid.ts", "src/ignored.ts",
    "src/ancestor-hidden.ts", "src/missing.ts", "context.json", "src/a.ts",
  ])
  assert_eq(report.paths.length(), 8)
  assert_eq(report.candidate_count, 4)
  assert_eq(report.accepted_count, 1)
  assert_eq(
    report.read_bytes,
    body.length().to_int64() + 2L + @utf8.encode(secret).length().to_int64(),
  )
  assert_true(report.security is Excluded)
  let decisions = Map::from_array(report.paths.map(path => (path.path, path)))
  assert_eq(
    (decisions["src/a.ts"].status, decisions["src/a.ts"].stage),
    ("accepted", "complete"),
  )
  assert_eq(
    (decisions["src/binary.ts"].stage, decisions["src/binary.ts"].reason),
    ("input", "Binary"),
  )
  assert_eq(decisions["src/invalid.ts"].reason, "InvalidUtf8")
  assert_eq(
    (decisions["src/secret.ts"].stage, decisions["src/secret.ts"].reason),
    ("security", "SecurityFinding"),
  )
  assert_true(decisions["src/secret.ts"].finding_count > 0)
  assert_false(decisions["src/secret.ts"].finding_rules.is_empty())
  assert_eq(decisions["src/missing.ts"].reason, "MissingFile")
  assert_eq(decisions["context.json"].reason, "OutputFile")
  guard decisions["src/ignored.ts"].origin is Some(local_origin) else {
    fail("expected local rule location")
  }
  guard decisions["src/ancestor-hidden.ts"].origin is Some(ancestor) else {
    fail("expected ancestor rule location")
  }
  assert_eq(local_origin.source, Some(".repomixignore"))
  assert_eq(ancestor.source, None)
  let text = report.to_json().stringify()
  assert_false(text.contains(secret))
  assert_false(text.contains("export const answer"))
  assert_false(text.contains(temp))
  assert_false(text.contains("ignored*.ts"))
  assert_false(text.contains("ancestor-*.ts"))
  assert_eq(@fs.read_file(output).text(), "OLD OUTPUT")
  let host = explain_selection({ ..options, file_paths: Some(["src/a.ts"]), }, [
    "src/secret.ts", "src/a.ts",
  ])
  assert_eq(host.paths.map(path => (path.path, path.reason)), [
    ("src/a.ts", "Accepted"),
    ("src/secret.ts", "NotListed"),
  ])
  assert_eq(host.read_bytes, body.length().to_int64())
  let empty = explain_selection(
    { ..options, file_paths: Some([]), max_files: 0, },
    ["src/secret.ts"],
  )
  assert_eq(empty.candidate_count, 0)
  assert_eq(empty.read_bytes, 0L)
  assert_eq(empty.paths[0].reason, "NotListed")
  let skipped = explain_selection({ ..options, max_file_size: 4, }, ["src/a.ts"])
  assert_eq(skipped.paths[0].reason, "TooLarge")
  assert_true(skipped.read_bytes <= 5L)
  let xml = explain_selection({ ..options, style: Style::Xml, }, ["src/xml.ts"])
  assert_eq(
    (xml.paths[0].stage, xml.paths[0].reason),
    ("format", "UnrepresentableText"),
  )
  let disabled = explain_selection({ ..options, security_check: false, }, [
    "src/secret.ts",
  ])
  assert_true(disabled.security is Disabled)
  assert_eq(disabled.accepted_count, 1)
  assert_eq(disabled.paths[0].finding_count, 0)
  assert_false(disabled.to_json().stringify().contains(secret))
  try explain_selection({ ..options, max_files: 0, }, ["src/a.ts"]) catch {
    InputLimitExceeded(kind~, limit~) => {
      assert_eq(kind, "maxFiles")
      assert_eq(limit, 0L)
    }
    err => raise err
  } noraise {
    _ => fail("expected candidate limit")
  }
  try
    explain_selection({ ..options, max_total_size: 0L, }, ["src/a.ts"])
  catch {
    InputLimitExceeded(kind~, limit~) => {
      assert_eq(kind, "maxTotalSize")
      assert_eq(limit, 0L)
    }
    err => raise err
  } noraise {
    _ => fail("expected query byte limit")
  }
  try explain_selection(options, ["../outside"]) catch {
    SelectionError => ()
    err => raise err
  } noraise {
    _ => fail("expected invalid literal query")
  }
  for paths in [Array::make(257, "src/a.ts"), ["a".repeat(4097)]] {
    try explain_selection(options, paths) catch {
      ConfigurationError => ()
      err => raise err
    } noraise {
      _ => fail("expected bounded path query")
    }
  }
}
