///|
test "library options select formats and their matching output filenames" {
  assert_eq(@moon_repomix.options(".").style, @moon_repomix.Style::Xml)
  for
    (style, suffix) in [
      (@moon_repomix.Style::Xml, "xml"),
      (@moon_repomix.Style::Markdown, "md"),
      (@moon_repomix.Style::Json, "json"),
      (@moon_repomix.Style::Plain, "txt"),
    ] {
    let options = @moon_repomix.options(".", style~)
    assert_eq(options.style, style)
    assert_eq(options.output, "repomix-output." + suffix)
    assert_true(options.security_check)
    assert_false(options.full_metadata)
    assert_eq(options.file_paths, None)
  }
  assert_true(@moon_repomix.options(".", full_metadata=true).full_metadata)
  assert_eq(
    @moon_repomix.options(".", file_paths=Some([])).file_paths,
    Some([]),
  )
  let paths = ["src/a.mbt"]
  let precise = @moon_repomix.options(".", file_paths=Some(paths))
  paths.push("src/b.mbt")
  assert_eq(precise.file_paths, Some(["src/a.mbt"]))
}
