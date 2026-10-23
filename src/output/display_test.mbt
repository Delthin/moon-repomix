///|
test "presentation controls preserve the canonical document and exact body lines" {
  for
    (source, expected) in [
      ("", ""),
      ("\n", "1: \n"),
      ("a\n", "1: a\n"),
      ("a\n\nlast", "1: a\n2: \n3: last"),
      ("中文\r\n\r\nlast\r", "1: 中文\r\n2: \r\n3: last\r"),
    ] {
    let doc = @document.create([{ path: "x.mbt", text: source, }])
    let display = { ..@output.Display::default(), line_numbers: true, }
    guard @json.parse(@output.json(doc, display~))
      is { "files": { "x.mbt": String(actual), .. }, .. } else {
      fail("Missing displayed body")
    }
    assert_eq(actual, expected)
    assert_eq(doc.files[0].text, source)
  }
  let metadata : Json = { "custom": "unchanged" }
  let doc = @document.create(
    [{ path: "src/a.ts", text: "body\r\n", }],
    sections=[
      { kind: "git_diff", title: "Changes", text: "diff body\r\n", },
      { kind: "note", title: "Custom", text: "note body", },
    ],
    metadata~,
    header_text="header\r\n",
    instruction_text="instructions\r\n",
  )
  let display = {
    ..@output.Display::default(),
    path_prefix: "../project",
    line_numbers: true,
    file_summary: false,
    directory_structure: false,
    git_sections: false,
    metadata: false,
  }
  let rendered = @output.json(doc, display~)
  guard @json.parse(rendered)
    is {
      "files": { "../project/src/a.ts": String(body), .. },
      "sections": Array(sections),
      "headerText": String(header),
      "instructionText": String(instructions),
      ..
    } else {
    fail("Missing presentation fields")
  }
  assert_eq(body, "1: body\r\n")
  assert_eq(header, "header\r\n")
  assert_eq(instructions, "instructions\r\n")
  assert_eq(sections.length(), 1)
  assert_true(
    sections[0] is { "kind": String("note"), "text": String("note body"), .. },
  )
  assert_false(rendered.contains("\"notice\""))
  assert_false(rendered.contains("\"directoryStructure\""))
  assert_false(rendered.contains("\"metadata\""))
  let xml = @output.xml(doc, display~)
  assert_true(xml.contains("path=\"../project/src/a.ts\""))
  assert_true(xml.contains("1: body&#13;\n"))
  assert_false(xml.contains("<notice>"))
  assert_false(xml.contains("<directory_structure>"))
  assert_false(xml.contains("<metadata>"))
  assert_false(xml.contains("diff body"))
  let md = @output.markdown(doc, display~)
  assert_true(md.contains("## File: ../project/src/a.ts"))
  assert_true(md.contains("1: body\r\n"))
  assert_false(md.contains("## Directory structure"))
  assert_false(md.contains("untrusted data"))
  let plain = @output.plain(doc, display~)
  assert_true(plain.contains("File: \"../project/src/a.ts\""))
  assert_false(plain.contains("Directory Structure"))
  assert_true(plain.contains("note body"))
  assert_false(plain.contains("diff body"))
  let no_files = { ..display, files: false, }
  guard @json.parse(@output.json(doc, display=no_files))
    is { "files": Object(files), .. } else {
    fail("Missing stable empty files map")
  }
  assert_true(files.is_empty())
  for
    text in [
      @output.xml(doc, display=no_files),
      @output.markdown(doc, display=no_files),
      @output.plain(doc, display=no_files),
    ] {
    assert_false(text.contains("1: body"))
    assert_true(text.contains("header"))
    assert_true(text.contains("instructions"))
  }
  for
    (actual, explicit) in [
      (@output.json(doc), @output.json(doc, display=@output.Display::default())),
      (@output.xml(doc), @output.xml(doc, display=@output.Display::default())),
      (
        @output.markdown(doc),
        @output.markdown(doc, display=@output.Display::default()),
      ),
      (
        @output.plain(doc),
        @output.plain(doc, display=@output.Display::default()),
      ),
    ] {
    assert_eq(actual, explicit)
  }
  assert_eq(doc.files[0].path, "src/a.ts")
  assert_eq(doc.files[0].text, "body\r\n")
  assert_eq(doc.sections.length(), 2)
  assert_eq(doc.metadata, metadata)
}
