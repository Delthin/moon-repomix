///|
async test "bounded UTF-8 snapshots preserve newline bytes and skip unsafe inputs" {
  let dir = @fs.tmpdir(prefix="moon-repomix-input-")
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_file(dir + "/text", b"\xef\xbb\xbfA\r\nB\r", create_mode=CreateNew)
  match @input.read(dir + "/text", 8) {
    Loaded(snapshot) => {
      assert_eq(snapshot.text, "A\r\nB\r")
      assert_eq(snapshot.bom_bytes, 3)
      assert_eq(snapshot.disk_bytes, 8)
    }
    _ => fail("expected complete snapshot")
  }
  assert_true(@input.read(dir + "/text", 7) is Skipped("TooLarge"))
  @fs.write_file(dir + "/binary", b"a\x00b", create_mode=CreateNew)
  assert_true(@input.read(dir + "/binary", 20) is Skipped("Binary"))
  @fs.write_file(dir + "/invalid", b"\xff", create_mode=CreateNew)
  assert_true(@input.read(dir + "/invalid", 20) is Skipped("InvalidUtf8"))
  assert_true(@input.read(dir, 20) is Skipped("UnsupportedFileType"))
  assert_true(@input.read(dir + "/missing", 20) is Skipped("Unreadable"))
  let exact = @input.read_metered(dir + "/text", 8, 8L)
  assert_true(exact.result is Loaded(_))
  assert_eq(exact.read_bytes, 8L)
  let validated = @input.read_validated_metered(dir + "/text", 8, 8L)
  guard validated.result is Loaded(proof) else {
    fail("expected validated snapshot")
  }
  let snapshot = proof.snapshot()
  assert_eq(snapshot.text, "A\r\nB\r")
  assert_eq(snapshot.disk_bytes, 8)
  assert_eq(snapshot.bom_bytes, 3)
  assert_eq(validated.read_bytes, 8L)
  // Public facts can be copied and updated without changing the proof's text.
  let changed = { ..snapshot, text: "other", }
  assert_eq(changed.text, "other")
  assert_eq(proof.snapshot().text, "A\r\nB\r")
  try @input.read_validated_metered(dir + "/text", 8, 7L) catch {
    @input.TotalSizeLimitExceeded => ()
    _ => fail("unexpected validated raw-byte limit error")
  } noraise {
    _ => fail("validated reads retain the same excess-byte probe")
  }
  try @input.read_metered(dir + "/text", 8, 7L) catch {
    @input.TotalSizeLimitExceeded => ()
    _ => fail("unexpected raw-byte limit error")
  } noraise {
    _ => fail("the BOM and one-byte excess must count")
  }
  for
    (name, reason, bytes) in [
      ("binary", "Binary", 3L),
      ("invalid", "InvalidUtf8", 1L),
      ("missing", "Unreadable", 0L),
    ] {
    let result = @input.read_metered(dir + "/" + name, 20, 20L)
    assert_eq(result.read_bytes, bytes)
    assert_true(result.result is Skipped(why) && why == reason)
    let validated = @input.read_validated_metered(dir + "/" + name, 20, 20L)
    assert_eq(validated.read_bytes, bytes)
    assert_true(validated.result is Skipped(why) && why == reason)
  }
  let oversized = @input.read_metered(dir + "/text", 7, 0L)
  assert_true(oversized.result is Skipped("TooLarge"))
  assert_eq(oversized.read_bytes, 0L)
  @fs.write_file(dir + "/empty", b"", create_mode=CreateNew)
  let empty = @input.read_metered(dir + "/empty", 20, 0L)
  assert_true(empty.result is Loaded(_))
  assert_eq(empty.read_bytes, 0L)
  let validated_empty = @input.read_validated_metered(dir + "/empty", 20, 0L)
  guard validated_empty.result is Loaded(value) else {
    fail("expected validated empty")
  }
  assert_eq(value.snapshot().text, "")
  assert_eq(validated_empty.read_bytes, 0L)
}
