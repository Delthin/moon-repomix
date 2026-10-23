///|
async test "pack_volumes reuses scanned snapshots and counts independent complete documents" {
  let temp = @fs.tmpdir(prefix="moon-volumes-sdk-")
  defer @async.protect_from_cancel(() => @platform.remove_owned_tree(temp))
  @fs.mkdir(temp + "/src")
  let names = ["a.ts", "b.ts", "中文.ts"]
  let bodies : Map[String, String] = Map([])
  for index, name in names {
    let text = "export function item" +
      index.to_string() +
      "() {\r\n" +
      "  const entry = { name: 'source', count: 100 };\r\n".repeat(240) +
      "  return entry;\r\n}\r\n"
    bodies["src/" + name] = text
    @fs.write_file(temp + "/src/" + name, text, create_mode=CreateOrTruncate)
  }
  let secret = "gh" + "p_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
  @fs.write_file(
    temp + "/src/leak.ts",
    "const token = \"" + secret + "\";\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    temp + "/src/ignored.ts",
    "must not enter any volume",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    temp + "/.repomixignore",
    "src/ignored.ts\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    temp + "/instructions.txt",
    "review invariants\r\n",
    create_mode=CreateOrTruncate,
  )
  let cwd = @env.current_dir().unwrap()
  let runtime = Runtime::load(cwd + "/assets/tokenizer-o200k_base.tiktoken")
  for style in [Style::Json, Style::Xml, Style::Markdown, Style::Plain] {
    let base = options(
      temp,
      style~,
      compress=true,
      keep_full_patterns=["src/**"],
      header_text="review context",
      instruction_file_path=Some(temp + "/instructions.txt"),
      full_metadata=true,
      show_line_numbers=true,
    )
    let configured = { ..base, include_patterns: ["src/**"], }
    let complete = pack(configured, runtime)
    assert_eq(complete.files.length(), 3)
    assert_true(complete.security is Excluded)
    let limit = complete.tokens / 2
    // A single-document budget is separate from the required volume limit.
    let result = pack_volumes(
      { ..configured, token_budget: Some(1), },
      runtime,
      max_tokens=limit,
    )
    assert_true(result.partition.volumes.length() >= 2)
    assert_eq(result.files.length(), 3)
    assert_true(result.security is Excluded)
    assert_false(result.findings.is_empty())
    let seen : Set[String] = Set([])
    let mut total = result.partition.index_tokens.to_int64()
    for volume in result.partition.volumes {
      assert_true(volume.tokens <= limit)
      let extension = match style {
        Style::Json => ".json"
        Style::Xml => ".xml"
        Style::Markdown => ".md"
        Style::Plain => ".txt"
      }
      assert_eq(result.file_names[volume.id], volume.id + extension)
      assert_eq(runtime.encoder.count(volume.text), volume.tokens)
      assert_eq(@utf8.encode(volume.text).length(), volume.bytes)
      assert_eq(volume.document.header_text, "review context")
      assert_eq(volume.document.instruction_text, "review invariants\r\n")
      assert_true(volume.document.sections.is_empty())
      assert_false(volume.text.contains(secret))
      assert_false(volume.text.contains("must not enter"))
      for file in volume.document.files {
        assert_false(seen.contains(file.path))
        seen.add(file.path)
        assert_eq(Some(file.text), bodies.get(file.path))
      }
      guard volume.document.metadata is { "compression": Array(records), .. } else {
        fail("Missing per-volume compression projection")
      }
      assert_eq(records.length(), volume.document.files.length())
      for record in records {
        guard record
          is { "path": String(path), "reason": String("kept-full"), .. } else {
          fail("Invalid kept-full metadata")
        }
        assert_true(volume.document.files.any(file => file.path == path))
      }
      total += volume.tokens.to_int64()
    }
    assert_eq(seen.length(), 3)
    assert_eq(
      runtime.encoder.count(result.partition.index_text),
      result.partition.index_tokens,
    )
    assert_eq(total, result.partition.total_tokens)
    guard result.partition.index
      is { "files": Object(ownership), "metadata": original, .. } else {
      fail("Missing global manifest")
    }
    assert_eq(ownership.length(), 3)
    assert_eq(original, complete.document.metadata)
    for path in bodies.keys() {
      assert_true(ownership.contains(path))
    }
    guard result.partition.index is { "volumes": Array(rows), .. } else {
      fail("Missing named volume summaries")
    }
    assert_eq(rows.length(), result.partition.volumes.length())
    for row in rows {
      guard row is { "id": String(id), "fileName": String(name), .. } else {
        fail("Missing volume filename")
      }
      assert_eq(name, result.file_names[id])
    }
  }
  try pack_volumes(options(temp), runtime, max_tokens=0) catch {
    @partition.PartitionError::InvalidCap(0) => ()
    _ => fail("Wrong volume limit error")
  } noraise {
    _ => fail("Invalid limit was accepted")
  }
}
