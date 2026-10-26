///|
async test "bounded source pipeline preserves serial bodies, metadata order and exact file statistics" {
  let runtime = Runtime::load(
    @env.current_dir().unwrap() + "/assets/tokenizer-o200k_base.tiktoken",
  )
  let ts = "export function huge(x: number): number {\n  let sum = x;\n" +
    "  sum += 1;\n".repeat(80) +
    "  return sum;\n}\n"
  let go = "package p\n\nfunc Huge() int {\n  sum := 0\n" +
    "  sum += 1\n".repeat(80) +
    "  return sum\n}\n"
  // Deliberately not filename-sorted; a worker must not reorder caller results.
  let sources = [
    ("z.ts", ts, false),
    ("kept.ts", ts, true),
    ("empty.mbt", "", false),
    ("README.md", "ordinary text 中文 😀\r\n", false),
    ("a.ts", ts, false),
    ("b.go", go, false),
  ]
  let accepted : Array[@document.File] = []
  let files : Array[FileStats] = []
  let transforms : Array[Json] = []
  let pipeline = FilePipeline::new(runtime, true, accepted, files, transforms)
  defer pipeline.close()
  for i in 0..<sources.length() {
    let (path, text, kept_full) = sources[i]
    let bom_bytes = if i == 4 { 3 } else { 0 }
    pipeline.push(
      path,
      { text, disk_bytes: @utf8.encode(text).length() + bom_bytes, bom_bytes, },
      kept_full,
    )
    assert_true(pipeline.pending.length() < 4)
    assert_true(pipeline.pending_bytes <= 16 * 1024 * 1024)
  }
  pipeline.flush()
  assert_eq(accepted.length(), sources.length())
  assert_eq(files.length(), sources.length())
  assert_eq(transforms.length(), sources.length())
  for i in 0..<sources.length() {
    let (path, text, kept_full) = sources[i]
    let direct = @compression.compress(path, text)
    let expected_text = if kept_full { text } else { direct.text }
    assert_eq(accepted[i].path, path)
    assert_eq(accepted[i].text, expected_text)
    assert_eq(files[i].path, path)
    assert_eq(files[i].original_tokens, runtime.encoder.encode(text).length())
    assert_eq(files[i].tokens, runtime.encoder.encode(expected_text).length())
    let expected_bytes = @utf8.encode(text).length() +
      (if i == 4 { 3 } else { 0 })
    assert_eq(files[i].disk_bytes, expected_bytes)
    guard transforms[i]
      is {
        "path": String(recorded),
        "applied": applied,
        "ranges": Array(ranges),
        ..
      } else {
      fail("expected complete compression record")
    }
    assert_eq(recorded, path)
    if path == "z.ts" || path == "a.ts" || path == "b.go" {
      assert_true(direct.applied)
      assert_eq(applied, Json(true))
      assert_true(!ranges.is_empty())
    } else {
      assert_eq(applied, Json(false))
      assert_true(ranges.is_empty())
    }
  }
  assert_eq(pipeline.pending.length(), 0)
  assert_eq(pipeline.pending_bytes, 0)
  pipeline.close()
  assert_true(pipeline.planner is None)

  let raw : Array[@document.File] = []
  let raw_files : Array[FileStats] = []
  let raw_records : Array[Json] = []
  let raw_pipeline = FilePipeline::new(
    runtime, false, raw, raw_files, raw_records,
  )
  defer raw_pipeline.close()
  for (path, text, _) in sources {
    raw_pipeline.push(
      path,
      { text, disk_bytes: @utf8.encode(text).length(), bom_bytes: 0, },
      false,
    )
    assert_true(raw_pipeline.pending.is_empty())
  }
  raw_pipeline.flush()
  assert_true(!raw_pipeline.planner_attempted)
  assert_true(raw_pipeline.planner is None)
  assert_true(raw_records.is_empty())
  for i in 0..<sources.length() {
    let (path, text, _) = sources[i]
    assert_eq(raw[i].path, path)
    assert_eq(raw[i].text, text)
    assert_eq(raw_files[i].tokens, runtime.encoder.encode(text).length())
  }
}
