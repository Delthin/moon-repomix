///|
async test "pipeline teardown releases native leases after input failure and cancellation" {
  let runtime = Runtime::load(
    @env.current_dir().unwrap() + "/assets/tokenizer-o200k_base.tiktoken",
  )
  let body = "export function retained() {\n" +
    "  let count = 42;\n".repeat(1200) +
    "  return count;\n}\n"
  let size = @utf8.encode(body).length()
  let temp = @fs.tmpdir(prefix="moon-pipeline-cleanup-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(temp))
  @fs.mkdir(temp + "/.git")
  for i in 0..<6 {
    @fs.write_file(
      temp + "/" + i.to_string() + ".ts",
      body,
      create_mode=CreateOrTruncate,
    )
  }
  let limit = size.to_int64() * 4L
  try
    pack(
      options(temp, style=Json, compress=true, max_total_size=limit),
      runtime,
    )
  catch {
    InputLimitExceeded(kind~, limit~) => {
      assert_eq(kind, "maxTotalSize")
      assert_eq(limit, size.to_int64() * 4L)
    }
    err => raise err
  } noraise {
    _ => fail("expected byte quota failure after the first submitted batch")
  }
  // All four process-wide worker slots must be reusable after error teardown.
  let after_error = @compression.Planner::new(workers=4)
  after_error.close()

  let accepted : Array[@document.File] = []
  let stats : Array[FileStats] = []
  let transforms : Array[Json] = []
  let pipeline = FilePipeline::new(
    runtime.encoder.session(),
    true,
    accepted,
    stats,
    transforms,
  )
  defer pipeline.close()
  for i in 0..<4 {
    pipeline.push(
      "queued" + i.to_string() + ".ts",
      { text: body, disk_bytes: size, bom_bytes: 0, },
      false,
    )
  }
  assert_true(pipeline.has_active())
  let cancelled = @async.with_timeout_opt(1, async fn() {
    defer pipeline.close()
    @async.sleep(50)
  })
  assert_true(cancelled is None)
  assert_true(accepted.is_empty())
  assert_true(stats.is_empty())
  assert_true(transforms.is_empty())
  let after_cancel = @compression.Planner::new(workers=4)
  after_cancel.close()
}
