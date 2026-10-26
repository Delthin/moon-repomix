///|
test "necessary literal families preserve the complete pinned detector result" {
  let policy = @moon_scrub.ScanConfig::secrets_only()
  assert_true(policy.extra_prefixes.is_empty())
  assert_true(policy.extra_patterns.is_empty())
  let prefixes = [
    "github_pat_", "sk-ant-", "sk_live_", "rk_live_", "pk_live_", "dop_v1_", "dop_v2_",
    "shpat_", "shpca_", "shppa_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "gha_",
    "xoxb-", "xoxp-", "xoxc-", "xoxa-", "xoxr-", "glpat-", "npm_", "lin_api_", "glc_",
    "cko_", "key-", "nfp_", "pypi-AgEIcHlwaS5vcmc", "glrt-", "xoxe.x-xcs-", "ATATTx",
    "1//", "LTAI", "sntrys_", "AIza", "AKIA", "ASIA", "SG.", "sk-",
  ]
  let suffix = "a1Bc2De3Fg4Hi5Jk6Lm7No8Pq9Rs0Tu1Vw2Xy3Z"
  let bodies = [
    "",
    "ordinary source 中文 😀\r\n",
    "ey",
    "BEARER",
    "://",
    "@",
    "-----begin ",
    "----BEGIN ",
    "@ unrelated then " + ":// host",
  ]
  for prefix in prefixes {
    let token = prefix + suffix
    bodies.push(token)
    bodies.push("中文 😀\r\n'" + token + "'\n")
    bodies.push("first " + token + " second " + token + "!")
    assert_true((credential_candidates(token) & 1) != 0)
  }
  for
    label in [
      "PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "OPENSSH PRIVATE KEY",
      "ENCRYPTED PRIVATE KEY", "PGP PRIVATE KEY BLOCK", "DSA PRIVATE KEY",
    ] {
    let begin = "-----BEGIN " + label + "-----"
    bodies.push(begin)
    bodies.push(begin + "\r\nYWJj\r\n-----END " + label + "----- trailing")
    assert_true((credential_candidates(begin) & 8) != 0)
  }
  let jwt = "eyJ" +
    "hbGciOiJIUzI1NiJ9" +
    "." +
    "cGF5bG9hZA" +
    "." +
    "c2lnbmF0dXJl"
  let url = "https" + "://" + "reader:" + suffix + "@example.invalid/path"
  for bearer in ["bearer ", "BEARER ", "BeArEr "] {
    bodies.push(bearer + suffix)
  }
  bodies.push(jwt)
  bodies.push(url)
  bodies.push("password = '" + suffix + "'\r\n")
  bodies.push("Authorization: Basic " + "dXNlcjpwYXNz")
  bodies.push(
    "中文 😀\n" + url + " " + jwt + " bearer " + prefixes[0] + suffix,
  )
  for body in bodies {
    assert_eq(
      scan_credentials(body),
      @moon_scrub.scan_with_config(body, policy),
    )
    // Every ASCII truncation near a prefix is a complete independent input.
    // Existing public validation fixtures cover invalid surrogate interiors.
    let mut ascii = true
    for c in body {
      if c.to_int() > 127 {
        ascii = false
      }
    }
    if ascii {
      let limit = if body.length() < 28 { body.length() } else { 28 }
      for end in 0..<limit {
        let truncated = body[:end].to_owned()
        assert_eq(
          scan_credentials(truncated),
          @moon_scrub.scan_with_config(truncated, policy),
        )
      }
    }
  }
}
