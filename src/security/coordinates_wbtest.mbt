///|
test "policy-filtered engine hits need no disk coordinate pass" {
  let short = "sk" + "-" + "Ab9Cd8Ef7Gh6Ij5"
  assert_true(
    !@moon_scrub.scan_with_config(short, @moon_scrub.ScanConfig::secrets_only()).is_empty(),
  )
  assert_true(
    scan("filtered.txt", short + "尾巴 😀\r\n".repeat(3000), 0).is_empty(),
  )

  let before = "中文 😀\r\n" + short + "\n"
  let token = "gh" + "p_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
  assert_eq(token.length(), 40)
  let body = before + token + "\r\n" + "unrelated 中文 😀\r\n".repeat(3000)
  let expected_start = @utf8.encode(before).length() + 3
  assert_eq(scan("mixed.txt", body, 3), [
    {
      rule: "github-token",
      path: "mixed.txt",
      start: expected_start,
      end: expected_start + 40,
      line: 3,
    },
  ])
  let scalar = "a😀b"
  for i in [0, 1, 3, 4] {
    assert_true(scalar_boundary(scalar, i))
  }
  for i in [-1, 2, 5] {
    assert_true(!scalar_boundary(scalar, i))
  }
}
