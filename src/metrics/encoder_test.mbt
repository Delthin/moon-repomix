///|
priv struct Golden {
  name : String
  text : String
  ids : Array[Int32]
} derive(FromJson)

///|
async fn assets_dir() -> String {
  match @env.get_env_var("TOKENIZER_ASSETS") {
    Some(path) => path
    None => @fs.realpath("assets")
  }
}

///|
async test "ordinary o200k IDs match independent tiktoken 0.14.0 golden" {
  let assets = assets_dir()
  let encoder = @metrics.Encoder::load(
    assets + "/tokenizer-o200k_base.tiktoken",
  )
  let cases : Array[Golden] = @json.from_json(
    @json.parse(@fs.read_file(assets + "/tokenizer-golden.json").text()),
  )
  assert_eq(cases.length(), 104)
  for case in cases {
    assert_eq(encoder.encode(case.text), case.ids, msg=case.name)
    assert_eq(encoder.count(case.text), case.ids.length(), msg=case.name)
  }
  // Reuse does not retain mutable per-call merge state; totals are not sums
  // of fragments, even without any added wrapping bytes.
  assert_eq(encoder.encode("hello"), [24912])
  assert_eq(encoder.encode("helloworld"), [10844, 192256])
  assert_eq(encoder.count("hel") + encoder.count("lo"), 2)
  assert_eq(encoder.count("hello"), 1)
  assert_eq(encoder.encode("hello"), [24912])
  // The count memo is scoped to exact regex pieces in one call. Full encoding
  // does not use it, so repeated/Unicode pieces exercise the memo independently.
  let repeated = "antidisestablishmentarianism MixedCaseIdentifier123 中文 😀\n".repeat(
    128,
  )
  let expected = encoder.encode(repeated).length()
  assert_eq(encoder.count(repeated), expected)
  assert_eq(encoder.count(repeated), expected)
}

///|
async test "absolute resources, checksums, IO failure and cancellation" {
  let assets = assets_dir()
  let dir = @fs.tmpdir(prefix="moon-repomix-tokenizer-")
  defer @fs.rmdir(dir, recursive=true)
  let ranks_path = dir + "/tokenizer-o200k_base.tiktoken"
  let unicode_path = dir + "/tokenizer-unicode-16.0.0.txt"
  let mut rejected = false
  ignore(@metrics.Encoder::load("assets/tokenizer-o200k_base.tiktoken")) catch {
    @metrics.ResourceError(message) => {
      assert_eq(message, "o200k ranks path must be absolute")
      rejected = true
    }
    error => raise error
  }
  assert_true(rejected)
  @fs.write_file(ranks_path, "corrupt", create_mode=CreateOrTruncate)
  rejected = false
  ignore(@metrics.Encoder::load(ranks_path)) catch {
    @metrics.ResourceError(message) => {
      assert_eq(message, "SHA-256 mismatch: o200k ranks")
      rejected = true
    }
    error => raise error
  }
  assert_true(rejected)
  let ranks = @fs.read_file(assets + "/tokenizer-o200k_base.tiktoken")
  @fs.write_file(ranks_path, ranks, create_mode=CreateOrTruncate)
  rejected = false
  ignore(@metrics.Encoder::load(ranks_path)) catch {
    @metrics.ResourceError(_) =>
      fail("missing Unicode file must retain its IO error")
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      rejected = true
    }
  }
  assert_true(rejected)
  @fs.write_file(unicode_path, "corrupt", create_mode=CreateOrTruncate)
  rejected = false
  ignore(@metrics.Encoder::load(ranks_path)) catch {
    @metrics.ResourceError(message) => {
      assert_eq(message, "SHA-256 mismatch: Unicode categories")
      rejected = true
    }
    error => raise error
  }
  assert_true(rejected)
  @fs.write_file(
    unicode_path,
    @fs.read_file(assets + "/tokenizer-unicode-16.0.0.txt"),
    create_mode=CreateOrTruncate,
  )
  let encoder = @metrics.Encoder::load(ranks_path)
  assert_eq(encoder.encode("Привет"), [23881, 131903])
  let cancelled = @async.with_task_group(group => {
    let task = group.spawn(async fn() { @metrics.Encoder::load(ranks_path) })
    @async.pause()
    task.cancel()
    try {
      ignore(task.wait())
      false
    } catch {
      error =>
        if @async.is_cancellation_error(error) {
          true
        } else {
          raise error
        }
    }
  })
  assert_true(cancelled)
}
