///|
test "UTF16 engine positions become disk UTF8 byte positions" {
  let token = "ghp_" + "Ab12".repeat(9)
  let text = "中😀e\u0301\r\n" + token
  let engine = @moon_scrub.scan_with_config(
    text,
    @moon_scrub.ScanConfig::secrets_only(),
  )
  assert_eq(engine[0].start, 7) // UTF-16: emoji occupies two units, not one.
  assert_eq(engine[0].end, 47)
  let hits = @security.scan("src/a.mbt", text, 3)
  assert_eq(hits, [
    { rule: "github-token", path: "src/a.mbt", start: 15, end: 55, line: 2, },
  ])
  let plain = @security.scan("a", "x\r" + token + "\n" + token, 0)
  assert_eq(plain[0].line, 2)
  assert_eq(plain[1].line, 3)
  try @security.scan("a", text, 1) catch {
    @security.ScanError::InvalidBomOffset => ()
    _ => fail("unexpected error category")
  } noraise {
    _ => fail("expected invalid BOM offset")
  }
}

///|
test "selected rule coverage uses synthetic secrets" {
  let samples = [
    ("ghp_" + "Ab12".repeat(9), "github-token"),
    ("github_pat_" + "Ab12".repeat(20) + "xy", "github-token"),
    ("AKIA" + "A1B2".repeat(4), "aws-access-key"),
    ("ASIA" + "A1B2".repeat(4), "aws-access-key"),
    ("sk-" + "Ab12".repeat(12), "openai-key"),
    ("sk-proj-" + "Ab12".repeat(20), "openai-key"),
    (
      "-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----", "pem-private-key",
    ),
    ("password=\"Correct-Horse-42!\"", "credential-assignment"),
    ("password=\"+Passw0rd+\"", "credential-assignment"),
    ("password=\" + Secret99 + \"", "credential-assignment"),
    ("password=' + Secret99 + '", "credential-assignment"),
  ]
  for prefix in ["gho_", "ghu_", "ghs_", "ghr_"] {
    assert_eq(
      @security.scan("fixture", prefix + "Ab12".repeat(9), 0)[0].rule,
      "github-token",
    )
  }
  assert_eq(
    @security.scan("fixture", "sk-svcacct-" + "Ab12".repeat(20), 0)[0].rule,
    "openai-key",
  )
  for
    marker in [
      "RSA PRIVATE KEY", "EC PRIVATE KEY", "OPENSSH PRIVATE KEY", "ENCRYPTED PRIVATE KEY",
      "PGP PRIVATE KEY BLOCK", "DSA PRIVATE KEY",
    ] {
    assert_eq(
      @security.scan("fixture", "-----BEGIN " + marker + "-----", 0)[0].rule,
      "pem-private-key",
    )
  }
  for (text, rule) in samples {
    let hits = @security.scan("fixture", text, 0)
    assert_eq(hits.length(), 1)
    assert_eq(hits[0].rule, rule)
  }
}

///|
test "length placeholders ordinary code and contact information are negative" {
  for
    text in [
      "ghp_Ab12Ab12",
      "ghp_" + "Ab12".repeat(10),
      "AKIA" + "A1B2".repeat(5),
      "sk-Ab12Ab12Ab12",
      "ghp_" + "x".repeat(36),
      "password=\"your_password_here\"",
      "token = process.env.API_TOKEN",
      "password: String",
      "secret = config.secret_value",
      "let token = parse_token(input)",
      "put(input + \"/credentials.txt\", \"token=\" + secret + \"\\n\")",
      "emit('password=' + config.secret + '\\n')",
      "emit(\"token=\" + api_key + \"\\n\")",
      "emit(\"quoted \\\"text\\\"\", \"secret=\" + my_secret + \"\\n\")",
      "contact person@company.dev +1-202-555-0199 192.168.1.1",
    ] {
    assert_eq(@security.scan("negative", text, 0).length(), 0)
  }
}
