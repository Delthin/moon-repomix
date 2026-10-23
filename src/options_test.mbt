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
    assert_true(
      options.file_summary &&
      options.directory_structure &&
      options.include_files,
    )
    assert_true(options.git_sections && options.metadata)
    assert_false(options.show_line_numbers)
    assert_eq(
      options.output_file_path_style,
      @moon_repomix.PathStyle::TargetRelative,
    )
    assert_eq(options.file_paths, None)
    assert_eq(options.keep_full_patterns, [])
    assert_eq(options.header_text, "")
    assert_eq(options.instruction_file_path, None)
  }
  let displayed = @moon_repomix.options(
    ".",
    file_summary=false,
    directory_structure=false,
    include_files=false,
    git_sections=false,
    metadata=false,
    show_line_numbers=true,
    output_file_path_style=@moon_repomix.PathStyle::CwdRelative,
  )
  assert_false(
    displayed.file_summary ||
    displayed.directory_structure ||
    displayed.include_files,
  )
  assert_false(displayed.git_sections || displayed.metadata)
  assert_true(displayed.show_line_numbers)
  assert_eq(
    displayed.output_file_path_style,
    @moon_repomix.PathStyle::CwdRelative,
  )
  assert_true(@moon_repomix.options(".", full_metadata=true).full_metadata)
  assert_eq(
    @moon_repomix.options(".", file_paths=Some([])).file_paths,
    Some([]),
  )
  let paths = ["src/a.mbt"]
  let precise = @moon_repomix.options(".", file_paths=Some(paths))
  paths.push("src/b.mbt")
  assert_eq(precise.file_paths, Some(["src/a.mbt"]))
  let keep = ["src/core/**"]
  let mixed = @moon_repomix.options(".", compress=true, keep_full_patterns=keep)
  keep.push("README.md")
  assert_eq(mixed.keep_full_patterns, ["src/core/**"])
  let templates = @moon_repomix.options(
    ".",
    header_text="SDK header",
    instruction_file_path=Some("notes.md"),
  )
  assert_eq(templates.header_text, "SDK header")
  assert_eq(templates.instruction_file_path, Some("notes.md"))
  assert_eq(
    @moon_repomix.options(".", instruction_file_path=Some("")).instruction_file_path,
    None,
  )
}
