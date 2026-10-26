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
    ("more.ts", ts, false),
    ("tail.txt", "last unsupported", false),
    ("more.go", go, false),
  ]
  let accepted : Array[@document.File] = []
  let files : Array[FileStats] = []
  let transforms : Array[Json] = []
  let pipeline = FilePipeline::new(
    runtime.encoder.session(),
    true,
    accepted,
    files,
    transforms,
  )
  defer pipeline.close()
  for i in 0..<sources.length() {
    let (path, text, kept_full) = sources[i]
    let bom_bytes = if i == 4 { 3 } else { 0 }
    pipeline.push(
      path,
      { text, disk_bytes: @utf8.encode(text).length() + bom_bytes, bom_bytes, },
      kept_full,
    )
    assert_true(pipeline.lanes.length() <= 3)
    assert_true(pipeline.active_bytes <= 16 * 1024 * 1024)
    let mut accounted = 0
    for lane in pipeline.lanes {
      if lane.active is Some(active) {
        accounted += active.bytes
      }
    }
    assert_eq(pipeline.active_bytes, accounted)
    assert_true(accepted.is_empty())
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
    if path == "z.ts" ||
      path == "a.ts" ||
      path == "b.go" ||
      path == "more.ts" ||
      path == "more.go" {
      assert_true(direct.applied)
      assert_eq(applied, Json(true))
      assert_true(!ranges.is_empty())
    } else {
      assert_eq(applied, Json(false))
      assert_true(ranges.is_empty())
    }
  }
  assert_true(!pipeline.has_active())
  assert_eq(pipeline.active_bytes, 0)
  assert_true(pipeline.completed.is_empty())
  pipeline.close()
  assert_true(pipeline.lanes.is_empty())

  // Synthetic byte weights exercise queue boundaries without allocating large
  // fixtures. Public snapshot byte/UTF-8 accuracy is tested by input/scan tests.
  for weights in [[8, 8, 1], [7, 7, 3]] {
    let weighted_output : Array[@document.File] = []
    let weighted_files : Array[FileStats] = []
    let weighted_records : Array[Json] = []
    let weighted = FilePipeline::new(
      runtime.encoder.session(),
      true,
      weighted_output,
      weighted_files,
      weighted_records,
    )
    defer weighted.close()
    let text = "export function sized(): number { return 3 }\n"
    for i in 0..<weights.length() {
      weighted.push(
        "weighted-\{i}.ts",
        { text, disk_bytes: weights[i] * 1024 * 1024, bom_bytes: 0, },
        false,
      )
      assert_true(weighted.active_bytes <= 16 * 1024 * 1024)
      assert_true(weighted.lanes.length() <= 3)
      assert_true(weighted_output.is_empty())
    }
    weighted.flush()
    weighted.close()
    assert_eq(weighted_output.length(), weights.length())
    for i in 0..<weights.length() {
      assert_eq(weighted_output[i].path, "weighted-\{i}.ts")
    }
  }

  // Completion order is deliberately reversed independently of OS scheduling.
  let reversed : Array[@document.File] = []
  let reversed_files : Array[FileStats] = []
  let reversed_records : Array[Json] = []
  let reorder = FilePipeline::new(
    runtime.encoder.session(),
    true,
    reversed,
    reversed_files,
    reversed_records,
  )
  defer reorder.close()
  for ordinal in [2, 0, 1] {
    let text = "value-\{ordinal}"
    reorder.record_serial({
      ordinal,
      path: "entry-\{ordinal}.txt",
      snapshot: { text, disk_bytes: @utf8.encode(text).length(), bom_bytes: 0, },
      kept_full: true,
    })
  }
  reorder.flush()
  reorder.flush()
  assert_eq(reversed.length(), 3)
  assert_eq(reversed_files.length(), 3)
  assert_eq(reversed_records.length(), 3)
  for i in 0..<3 {
    assert_eq(reversed[i].path, "entry-\{i}.txt")
    assert_eq(reversed[i].text, "value-\{i}")
    assert_eq(reversed_files[i].path, "entry-\{i}.txt")
    guard reversed_records[i] is { "path": String(path), .. } else {
      fail("missing reordered path")
    }
    assert_eq(path, "entry-\{i}.txt")
  }

  // Use real process-global leases to exercise constructor and submission
  // fallback; no production fault hook or relaxed result assertion is needed.
  let fallback_source = "export function fallback(): number { return 123456789; }\n"
  let fallback_snapshot : @input.Snapshot = {
    text: fallback_source,
    disk_bytes: @utf8.encode(fallback_source).length(),
    bom_bytes: 0,
  }
  let occupied = @compression.Planner::new(workers=4)
  let denied_output : Array[@document.File] = []
  let denied = FilePipeline::new(
    runtime.encoder.session(),
    true,
    denied_output,
    [],
    [],
  )
  defer denied.close()
  denied.push("constructor.ts", fallback_snapshot, false)
  assert_true(denied.creation_disabled)
  assert_true(denied.lanes.is_empty())
  denied.flush()
  assert_eq(
    denied_output[0].text,
    @compression.compress("constructor.ts", fallback_source).text,
  )
  occupied.close()
  denied.close()

  let submit_output : Array[@document.File] = []
  let submit_fallback = FilePipeline::new(
    runtime.encoder.session(),
    true,
    submit_output,
    [],
    [],
  )
  defer submit_fallback.close()
  submit_fallback.push("before.ts", fallback_snapshot, false)
  submit_fallback.flush()
  assert_eq(submit_fallback.lanes.length(), 1)
  let lease_holder = @compression.Planner::new(workers=3)
  defer lease_holder.close()
  let held = lease_holder.submit([
    { path: "lease-0.ts", text: fallback_source, },
    { path: "lease-1.ts", text: fallback_source, },
    { path: "lease-2.ts", text: fallback_source, },
    { path: "lease-3.ts", text: fallback_source, },
  ])
  submit_fallback.push("after.ts", fallback_snapshot, false)
  assert_true(submit_fallback.creation_disabled)
  assert_true(submit_fallback.lanes[0].failed)
  submit_fallback.flush()
  assert_eq(submit_output.length(), 2)
  assert_eq(submit_output[0].path, "before.ts")
  assert_eq(submit_output[1].path, "after.ts")
  assert_eq(
    submit_output[1].text,
    @compression.compress("after.ts", fallback_source).text,
  )
  ignore(held.finish())
  lease_holder.close()
  submit_fallback.close()

  let raw : Array[@document.File] = []
  let raw_files : Array[FileStats] = []
  let raw_records : Array[Json] = []
  let raw_pipeline = FilePipeline::new(
    runtime.encoder.session(),
    false,
    raw,
    raw_files,
    raw_records,
  )
  defer raw_pipeline.close()
  for (path, text, _) in sources {
    raw_pipeline.push(
      path,
      { text, disk_bytes: @utf8.encode(text).length(), bom_bytes: 0, },
      false,
    )
    assert_true(raw_pipeline.lanes.is_empty())
    assert_eq(raw_pipeline.active_bytes, 0)
  }
  raw_pipeline.flush()
  assert_true(raw_pipeline.lanes.is_empty())
  assert_true(raw_records.is_empty())
  for i in 0..<sources.length() {
    let (path, text, _) = sources[i]
    assert_eq(raw[i].path, path)
    assert_eq(raw[i].text, text)
    assert_eq(raw_files[i].tokens, runtime.encoder.encode(text).length())
  }
}
