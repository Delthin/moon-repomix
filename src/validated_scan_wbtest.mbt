///|
async test "reader-validated scanning preserves the public scan and disk coordinates" {
  let dir = @fs.tmpdir(prefix="moon-validated-scan-")
  defer @fs.rmdir(dir, recursive=true)
  let token = "ghp_" + "Ab12".repeat(9)
  let assignment = "password" + "=\"" + "Correct-Horse-42!" + "\""
  let pem = "-----BEGIN " + "RSA PRIVATE KEY-----\r\nsynthetic"
  for
    (bom, text) in [
      (0, ""),
      (3, ""),
      (0, "ordinary code 中文 😀\r\n"),
      (3, "\uFEFF中文 e\u0301\r\n"),
      (0, token),
      (3, "中😀e\u0301\r\n" + token),
      (0, "x\r" + token + "\n" + assignment),
      (3, pem + "\n" + assignment),
      (0, "\uFFFF\r\n" + token),
    ] {
    let bytes = @utf8.encode((if bom == 3 { "\uFEFF" } else { "" }) + text)
    @fs.write_file(dir + "/source", bytes, create_mode=CreateOrTruncate)
    let read = @input.read_validated_metered(dir + "/source", 4096, 4096L)
    guard read.result is Loaded(value) else { fail("expected validated text") }
    assert_eq(value.snapshot().text, text)
    assert_eq(value.snapshot().bom_bytes, bom)
    assert_eq(value.snapshot().disk_bytes, bytes.length())
    assert_eq(read.read_bytes, bytes.length().to_int64())
    assert_eq(
      @security.scan_validated("source", value.validated_text()),
      @security.scan("source", text, bom),
    )
  }
  for bytes in [b"a\x00b", b"\xff", b"\xed\xa0\x80", b"\xed\xb0\x80"] {
    @fs.write_file(dir + "/source", bytes, create_mode=CreateOrTruncate)
    let read = @input.read_validated_metered(dir + "/source", 4096, 4096L)
    assert_true(read.result is Skipped(_))
    assert_eq(read.read_bytes, bytes.length().to_int64())
  }
}
