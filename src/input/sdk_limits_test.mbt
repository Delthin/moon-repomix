///|
async fn assert_sdk_limit(
  options : @moon_repomix.Options,
  runtime : @moon_repomix.Runtime,
  kind : String,
  limit : Int64,
) -> Unit {
  for volumes in [false, true] {
    try {
      if volumes {
        ignore(@moon_repomix.pack_volumes(options, runtime, max_tokens=20000))
      } else {
        ignore(@moon_repomix.pack(options, runtime))
      }
    } catch {
      @moon_repomix.PackError::InputLimitExceeded(kind=actual, limit=bound) => {
        // Fixed error fields are the whole payload: never paths or file text.
        assert_eq(actual, kind)
        assert_eq(bound, limit)
      }
      _ => fail("unexpected SDK input-limit error")
    } noraise {
      _ => fail("single and volumes must enforce the same input budget")
    }
  }
}

///|
async test "single and volume packing budget candidates and all raw excluded input bytes" {
  let dir = @fs.tmpdir(prefix="moon-repomix-sdk-limits-")
  defer @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
  @fs.write_file(dir + "/a-bom.txt", b"\xef\xbb\xbfok", create_mode=CreateNew)
  @fs.write_file(dir + "/b-invalid.txt", b"\xff", create_mode=CreateNew)
  let secret = "gh" + "p_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
  @fs.write_file(dir + "/c-secret.txt", secret, create_mode=CreateNew)
  @fs.write_file(dir + "/d-binary.txt", b"\x00xy", create_mode=CreateNew)
  @fs.write_file(dir + "/e-tail.txt", "z", create_mode=CreateNew)
  @fs.write_file(
    dir + "/ignored.txt",
    "ignored".repeat(100),
    create_mode=CreateNew,
  )
  @fs.write_file(dir + "/empty.dat", b"", create_mode=CreateNew)
  let runtime = @moon_repomix.Runtime::load(
    @env.current_dir().unwrap() + "/assets/tokenizer-o200k_base.tiktoken",
  )
  // 5 BOM/raw bytes + 1 invalid byte + 40 secret bytes + 3 binary bytes + 1 tail.
  let base = {
    ..@moon_repomix.options(dir, max_files=5, max_total_size=50L),
    include_patterns: ["*.txt"],
    ignore: ["ignored.txt"],
  }
  let single = @moon_repomix.pack(base, runtime)
  assert_eq(single.files.map(f => f.path), ["a-bom.txt", "e-tail.txt"])
  assert_true(single.skipped.any(s => s.reason == "InvalidUtf8"))
  assert_true(single.skipped.any(s => s.reason == "Binary"))
  assert_true(single.security is Excluded)
  assert_false(single.text.contains(secret))
  let volumes = @moon_repomix.pack_volumes(base, runtime, max_tokens=20000)
  assert_eq(
    volumes.files.map(f => (f.path, f.disk_bytes)),
    single.files.map(f => (f.path, f.disk_bytes)),
  )
  assert_true(volumes.security is Excluded)
  assert_sdk_limit({ ..base, max_files: 4, }, runtime, "maxFiles", 4L)
  assert_sdk_limit({ ..base, max_files: 0, }, runtime, "maxFiles", 0L)
  assert_sdk_limit(
    { ..base, max_total_size: 49L, },
    runtime,
    "maxTotalSize",
    49L,
  )
  for
    (first, budget) in [
      ("a-bom.txt", 5L),
      ("b-invalid.txt", 1L),
      ("c-secret.txt", 40L),
      ("d-binary.txt", 3L),
    ] {
    assert_sdk_limit(
      {
        ..base,
        file_paths: Some([first, "e-tail.txt"]),
        max_total_size: budget,
      },
      runtime,
      "maxTotalSize",
      budget,
    )
  }
  let empty = {
    ..base,
    file_paths: Some([]),
    max_files: 0,
    max_total_size: 0L,
  }
  assert_eq(@moon_repomix.pack(empty, runtime).files.length(), 0)
  assert_eq(
    @moon_repomix.pack_volumes(empty, runtime, max_tokens=20000).files.length(),
    0,
  )
  let empty_file = {
    ..base,
    include_patterns: [],
    file_paths: Some(["empty.dat", "ignored.txt"]),
    max_files: 1,
    max_total_size: 0L,
  }
  assert_eq(@moon_repomix.pack(empty_file, runtime).files.length(), 1)
  assert_eq(
    @moon_repomix.pack_volumes(empty_file, runtime, max_tokens=20000).files.length(),
    1,
  )
  // Public record construction must not bypass validation in prepare_pack.
  for
    invalid in [
      { ..base, max_files: -1, },
      { ..base, max_total_size: 9007199254740992L, },
    ] {
    try @moon_repomix.pack(invalid, runtime) catch {
      @moon_repomix.PackError::ConfigurationError => ()
      _ => fail("unexpected invalid-record error")
    } noraise {
      _ => fail("public options records still require validation")
    }
  }
}
