///|
async test "atomic replacement and executable-relative resource paths" {
  let dir = @fs.tmpdir(prefix="moon-repomix-commit-")
  defer @fs.rmdir(dir, recursive=true)
  let output = dir + "/上下文.xml"
  @platform.commit(output, "old")
  @platform.commit(output, "new\r\n")
  assert_eq(@fs.read_file(output).binary(), b"new\r\n")
  try @platform.create_new(output, "overwrite") catch {
    _ => ()
  } noraise {
    _ => fail("create_new overwrote an existing file")
  }
  assert_eq(@fs.read_file(output).binary(), b"new\r\n")
  try @platform.commit(dir, "directory") catch {
    _ => ()
  } noraise {
    _ => fail("a directory must not be replaced")
  }
  assert_eq(@fs.readdir(dir).length(), 1)
  let executable = @platform.executable_path()
  assert_true(@fs.kind(executable) is Regular)
  assert_true(
    @platform.tokenizer_path().has_suffix(
      "/share/moon-repomix/o200k_base.tiktoken",
    ),
  )
}
