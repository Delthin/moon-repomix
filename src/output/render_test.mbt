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
test "Markdown uses a longer fence and a single escaped path heading" {
  let doc = @document.create([
    { path: "#a\n<script>.mbt", text: "````\n# injected\n```", },
  ])
  let md = @output.markdown(doc)
  assert_true(md.contains("## File: \\#a&#10;&lt;script&gt;.mbt"))
  assert_true(md.contains("`````moonbit\n````\n# injected\n```\n`````\n"))
  assert_true(@output.xml(@document.create([])).contains("<files>\n  </files>"))
}
