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
}
