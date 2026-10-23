///|
fn bytes(text : String) -> Int32 {
  @utf8.encode(text).length()
}

///|
fn no_metadata(_files : Array[Int32], _sections : Array[Int32]) -> Json {
  Json::null()
}

///|
fn run(
  doc : @document.Document,
  cap : Int32,
  render~ : (@document.Document) -> String raise,
  count~ : (String) -> Int32 raise = text => bytes(text),
) -> @partition.Partition raise {
  @partition.partition(doc, cap, render~, count~, project_metadata=(f, s) => {
    no_metadata(f, s)
  })
}

///|
suberror CallbackFailed {
  CallbackFailed(String)
}

///|
test "four renderers preserve atoms templates metadata and exact independent index" {
  // Direct construction deliberately bypasses Document::create's sorting.
  let doc : @document.Document = {
    files: [
      { path: "\u{10000}.txt", text: "astral\r\n", },
      { path: "z.txt", text: "", },
      { path: "\u{e000}.txt", text: "中😀\r<&>\n", },
      { path: "a/first.txt", text: "body", },
    ],
    sections: [
      { kind: "diff", title: "same", text: "first section", },
      { kind: "commit", title: "same", text: "second section", },
    ],
    metadata: { "unknownCustom": { "keep": true } },
    header_text: "HEADER中\r\n",
    instruction_text: "INSTRUCTIONS😀\n",
  }
  let renderers : Array[(@document.Document) -> String raise] = [
    doc => @output.xml(doc),
    doc => @output.json(doc),
    doc => @output.markdown(doc),
    doc => @output.plain(doc),
  ]
  for render in renderers {
    // Independently render each legal one-atom output to choose a safe cap.
    // Final expectations still count every actual complete volume, not sums.
    let mut cap = 0
    for file in doc.files {
      let single = @document.create(
        [file],
        metadata=Json::null(),
        header_text=doc.header_text,
        instruction_text=doc.instruction_text,
      )
      cap = Int32::max(cap, bytes(render(single)))
    }
    for section in doc.sections {
      let single = @document.create(
        [],
        sections=[section],
        metadata=Json::null(),
        header_text=doc.header_text,
        instruction_text=doc.instruction_text,
      )
      cap = Int32::max(cap, bytes(render(single)))
    }
    let projections : Array[(Array[Int32], Array[Int32])] = []
    let result = @partition.partition(
      doc,
      cap,
      render~,
      count=text => bytes(text),
      project_metadata=(files, sections) => {
        projections.push((files.copy(), sections.copy()))
        // Projection arguments are owned copies, not live index arrays.
        files.clear()
        sections.clear()
        Json::null()
      },
    )
    assert_true(result.volumes.length() > 1)
    assert_eq(projections[0], ([], []))
    assert_eq(projections[1], ([3, 1, 2, 0], [0, 1]))
    let file_indices : Array[Int32] = []
    let section_indices : Array[Int32] = []
    let paths : Map[String, Json] = Map([])
    let sections : Map[String, Json] = Map([])
    let mut total = bytes(result.index_text).to_int64()
    for i, volume in result.volumes {
      assert_eq(volume.id, "part-000\{i + 1}")
      assert_eq(volume.text, render(volume.document))
      assert_eq(volume.tokens, bytes(volume.text))
      assert_eq(volume.bytes, bytes(volume.text))
      assert_true(volume.tokens <= cap)
      assert_eq(volume.document.header_text, doc.header_text)
      assert_eq(volume.document.instruction_text, doc.instruction_text)
      assert_eq(volume.document.metadata, Json::null())
      assert_false(volume.text.contains("unknownCustom"))
      let expected_tree = volume.document.files
        .map(f => {
          match f.path {
            "a/first.txt" => "a/\n  first.txt"
            path => path
          }
        })
        .join("\n")
      assert_eq(@document.tree(volume.document), expected_tree)
      for j, original_index in volume.file_indices {
        file_indices.push(original_index)
        let actual = volume.document.files[j]
        assert_eq(actual.path, doc.files[original_index].path)
        assert_eq(actual.text, doc.files[original_index].text)
        paths[actual.path] = Json::string(volume.id)
      }
      for j, original_index in volume.section_indices {
        section_indices.push(original_index)
        let actual = volume.document.sections[j]
        assert_eq(actual.kind, doc.sections[original_index].kind)
        assert_eq(actual.title, "same")
        assert_eq(actual.text, doc.sections[original_index].text)
        sections[original_index.to_string()] = Json::string(volume.id)
      }
      total += bytes(volume.text).to_int64()
    }
    assert_eq(file_indices, [3, 1, 2, 0])
    assert_eq(section_indices, [0, 1])
    guard result.index
      is {
        "schemaVersion": Number(1, ..),
        "volumes": Array(summaries),
        "files": Object(actual_paths),
        "sections": Object(actual_sections),
        "metadata": metadata,
        ..
      } else {
      fail("expected schema v1 index")
    }
    assert_eq(actual_paths, paths)
    assert_eq(actual_sections, sections)
    assert_eq(metadata, doc.metadata)
    assert_eq(summaries.length(), result.volumes.length())
    for i, summary in summaries {
      let volume = result.volumes[i]
      assert_eq(summary, {
        "id": volume.id,
        "tokens": volume.tokens,
        "bytes": volume.bytes,
        "fileIndices": volume.file_indices,
        "sectionIndices": volume.section_indices,
      })
    }
    assert_false(result.index_text.contains("first section"))
    assert_false(result.index_text.contains("astral"))
    assert_eq(result.index_text, result.index.stringify() + "\n")
    assert_eq(@json.parse(result.index_text), result.index)
    assert_eq(result.index_tokens, bytes(result.index_text))
    assert_eq(result.total_tokens, total)
    let again = run(doc, cap, render~)
    assert_eq(again.index_text, result.index_text)
    assert_eq(again.volumes.map(v => v.text), result.volumes.map(v => v.text))
    let replacement : Json = {
      "original": result.index,
      "fileName": "part-0001.json",
    }
    let renamed = result.with_index(replacement, count=text => bytes(text))
    assert_eq(renamed.index, replacement)
    assert_eq(renamed.index_text, replacement.stringify() + "\n")
    assert_eq(renamed.index_tokens, bytes(renamed.index_text))
    assert_eq(
      renamed.total_tokens,
      result.total_tokens -
      result.index_tokens.to_int64() +
      renamed.index_tokens.to_int64(),
    )
    assert_eq(renamed.volumes.map(v => v.text), result.volumes.map(v => v.text))
    assert_eq(result.index_text, result.index.stringify() + "\n")
    try result.with_index(replacement, count=_ => -1) catch {
      @partition.PartitionError::InvalidCount(-1) => ()
      _ => fail("wrong reindex counter failure")
    } noraise {
      _ => fail("negative reindex count accepted")
    }
  }
}

///|
test "validation exact cap empty template oversized units and callback failures" {
  let empty = @document.create([], header_text="template")
  let render : (@document.Document) -> String raise = d => {
    d.header_text +
    d.files.map(f => f.text).join("") +
    d.sections.map(s => s.text).join("")
  }
  let result = run(empty, 8, render~)
  assert_eq(result.volumes.length(), 1)
  assert_eq(result.volumes[0].text, "template")
  assert_eq(result.volumes[0].tokens, 8)
  assert_eq(result.volumes[0].file_indices, [])
  assert_eq(result.volumes[0].section_indices, [])
  assert_true(result.index_tokens > 8) // The index has its own unbounded count.
  assert_eq(result.total_tokens, 8L + result.index_tokens.to_int64())
  for cap in [0, -1] {
    try run(empty, cap, render=_ => raise CallbackFailed("not called")) catch {
      @partition.PartitionError::InvalidCap(actual) => assert_eq(actual, cap)
      _ => fail("cap must be checked before callbacks")
    } noraise {
      _ => fail("expected invalid cap")
    }
  }
  let duplicate : @document.Document = {
    ..empty,
    files: [{ path: "a", text: "1", }, { path: "a", text: "2", }],
  }
  try
    run(duplicate, 100, render=_ => raise CallbackFailed("not called"))
  catch {
    @partition.PartitionError::DuplicatePath(path) => assert_eq(path, "a")
    _ => fail("duplicates must be checked before callbacks")
  } noraise {
    _ => fail("expected duplicate path")
  }
  try run(empty, 7, render~) catch {
    @partition.PartitionError::TemplateTooLarge(actual) => assert_eq(actual, 8)
    _ => fail("expected template error")
  } noraise {
    _ => fail("expected oversized template")
  }
  let file = @document.create([{ path: "canonical/a", text: "12", }])
  assert_eq(run(file, 2, render~).volumes[0].text, "12")
  try run(file, 1, render~) catch {
    @partition.PartitionError::UnitTooLarge(
      @partition.UnitIdentity::FilePath(path),
      actual
    ) => {
      assert_eq(path, "canonical/a")
      assert_eq(actual, 2)
    }
    _ => fail("expected file identity")
  } noraise {
    _ => fail("expected oversized file")
  }
  let section = @document.create([], sections=[
    { kind: "a", title: "same", text: "", },
    { kind: "b", title: "same", text: "12", },
  ])
  try run(section, 1, render~) catch {
    @partition.PartitionError::UnitTooLarge(
      @partition.UnitIdentity::SectionIndex(index),
      actual
    ) => {
      assert_eq(index, 1)
      assert_eq(actual, 2)
    }
    _ => fail("expected original section identity")
  } noraise {
    _ => fail("expected oversized section")
  }
  // Negative counts are rejected at template, candidate and index stages.
  for bad_text in ["", "12", "index"] {
    try
      run(file, 2, render~, count=text => {
        if text == bad_text || (bad_text == "index" && text.has_prefix("{")) {
          -1
        } else {
          bytes(text)
        }
      })
    catch {
      @partition.PartitionError::InvalidCount(actual) => assert_eq(actual, -1)
      _ => fail("expected invalid counter result")
    } noraise {
      _ => fail("expected invalid count")
    }
  }
  // Preserve arbitrary callback errors, including errors after a valid template.
  for stage in ["render", "count", "projection", "index"] {
    try
      @partition.partition(
        file,
        2,
        render=d => {
          if stage == "render" && !d.files.is_empty() {
            raise CallbackFailed(stage)
          }
          render(d)
        },
        count=text => {
          if (stage == "count" && text == "12") ||
            (stage == "index" && text.has_prefix("{")) {
            raise CallbackFailed(stage)
          }
          bytes(text)
        },
        project_metadata=(files, _) => {
          if stage == "projection" && !files.is_empty() {
            raise CallbackFailed(stage)
          }
          Json::null()
        },
      )
    catch {
      CallbackFailed(actual) => assert_eq(actual, stage)
      _ => fail("callback error was replaced")
    } noraise {
      _ => fail("expected callback error")
    }
  }
  let wide = run(file, 2147483647, render~, count=_ => 2147483647)
  assert_eq(wide.total_tokens, 4294967294L)
}

///|
test "nonmonotonic nonadditive counts and logarithmic content visits" {
  let doc = @document.create([
    { path: "a", text: "A", },
    { path: "b", text: "B", },
    { path: "c", text: "C", },
    { path: "d", text: "D", },
  ])
  let render : (@document.Document) -> String raise = d => {
    d.files.map(f => f.text).join("")
  }
  // A single atom is over cap, two atoms fit exactly, four do not.
  // Counting singleton outputs up front or adding their counts would fail.
  let result = run(doc, 3, render~, count=text => {
    match text {
      "" => 0
      "AB" | "CD" => 3
      _ => 99
    }
  })
  assert_eq(result.volumes.map(v => v.text), ["AB", "CD"])
  assert_eq(result.volumes.map(v => v.tokens), [3, 3])
  assert_eq(result.index_tokens, 99)
  assert_eq(result.total_tokens, 105L)
  let mut visits = 0
  let mut calls = 0
  let many = @document.create(
    Array::makei(16, i => { path: "file-\{i}", text: "x", }),
  )
  let split = run(
    many,
    1,
    render=d => {
      visits += d.files.length()
      render(d)
    },
    count=text => {
      calls += 1
      if text.has_prefix("{") {
        100
      } else {
        bytes(text)
      }
    },
  )
  assert_eq(split.volumes.length(), 16)
  assert_true(visits <= 16 * 5) // At most log2(16) + 1 content visits.
  assert_true(calls <= 2 * 16 + 1) // Includes template and index.
  assert_eq(split.volumes[0].id, "part-0001")
  assert_eq(split.volumes[15].id, "part-0016")
}
