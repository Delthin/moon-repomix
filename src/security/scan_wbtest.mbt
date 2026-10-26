///|
test "PEM prefilter preserves the pinned secrets-only engine findings" {
  let policy = @moon_scrub.ScanConfig::secrets_only()
  for
    marker in [
      "PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "OPENSSH PRIVATE KEY",
      "ENCRYPTED PRIVATE KEY", "PGP PRIVATE KEY BLOCK", "DSA PRIVATE KEY",
    ] {
    let begin = "-----BEGIN " + marker + "-----"
    let block = begin + "\r\nsynthetic\r\n-----END " + marker + "----- trailing"
    for
      text in [
        begin,
        block,
        "中😀e\u0301\n" + block,
        "\uFEFF" + block + "\n" + block,
      ] {
      let original = @moon_scrub.scan_with_config(text, policy)
      assert_true(original.iter().any(hit => hit.kind == PrivateKey))
      assert_eq(scan_credentials(text), original)
    }
  }
  let assignment = "password" + "=\"" + "Correct-Horse-42!" + "\""
  let bearer = "Bearer " + "Ab12".repeat(9)
  let jwt = "eyJ" +
    "Ab12".repeat(4) +
    "." +
    "Cd34".repeat(4) +
    "." +
    "Ef56".repeat(4)
  for text in [assignment, bearer, jwt] {
    let original = @moon_scrub.scan_with_config(text, policy)
    assert_true(!original.is_empty())
    assert_eq(scan_credentials(text), original)
  }
  for
    text in [
      "",
      "ordinary code 中文 😀",
      "-----BEGIN ",
      "----BEGIN PRIVATE KEY-----",
      "-----begin PRIVATE KEY-----",
      "-----BEGIN\tPRIVATE KEY-----",
      "-----BEGIN\nPRIVATE KEY-----",
      "-----END PRIVATE KEY-----",
      "-----BEGIN PUBLIC KEY-----",
      "a-----BEGINx PRIVATE KEY-----",
      "\uFEFF中😀\r\n-----BEGIN\u00a0PRIVATE KEY-----",
      assignment + "\n-----BEGIN " + "PRIVATE KEY-----\nsynthetic",
      bearer + "\n" + jwt + "\n-----BEGIN PUBLIC KEY-----",
    ] {
    assert_eq(
      scan_credentials(text),
      @moon_scrub.scan_with_config(text, policy),
    )
  }
}
