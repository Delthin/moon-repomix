///|
test "XML preserves parser-normalized characters and rejects forbidden code points" {
  let doc = @document.create([{ path: "a\r\n\t\"<&.txt", text: "A\r\nB\r<&>", }])
  let xml = @output.xml(doc)
  assert_true(xml.contains("path=\"a&#13;&#10;&#9;&quot;&lt;&amp;.txt\""))
  assert_true(xml.contains(">A&#13;\nB&#13;&lt;&amp;&gt;</file>"))
  assert_false(@output.xml_representable("\u{1}"))
  assert_false(@output.xml_representable("\u{fffe}"))
  assert_true(@output.xml_representable("中文😀\r\n\t"))
}

///|
test "document paths use UTF-8 lexical order and keep directory children together" {
  let doc = @document.create([
    { path: "z.mbt", text: "", },
    { path: "docs/deep/z.md", text: "", },
    { path: "src/x.mbt", text: "", },
    { path: "docs/b.md", text: "", },
    { path: "\u{10000}.txt", text: "", },
    { path: "alpha.longname", text: "", },
    { path: "\u{e000}.txt", text: "", },
    { path: "docs/a.md", text: "", },
  ])
  assert_eq(
    doc.files.map(file => file.path).join("|"),
    "alpha.longname|docs/a.md|docs/b.md|docs/deep/z.md|src/x.mbt|z.mbt|\u{e000}.txt|\u{10000}.txt",
  )
  assert_eq(
    @document.tree(doc),
    "alpha.longname\ndocs/\n  a.md\n  b.md\n  deep/\n    z.md\nsrc/\n  x.mbt\nz.mbt\n\u{e000}.txt\n\u{10000}.txt",
  )
}

///|
test "Markdown uses a longer fence and a single escaped path heading" {
  let doc = @document.create([
    { path: "#a\n<script>.mbt", text: "````\n# injected\n```", },
  ])
  let md = @output.markdown(doc)
  assert_true(md.contains("## File: \\#a&#10;&lt;script&gt;.mbt"))
  assert_true(md.contains("`````moonbit\n````\n# injected\n```\n`````\n"))
  assert_true(@output.xml(@document.create([])).contains("<files>\n  </files>"))
}
