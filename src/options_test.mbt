///|
test "library release version and default output options" {
  assert_eq(@moon_repomix.version(), "0.5.1")
  let defaults = @moon_repomix.options(".")
  assert_eq(defaults.style, @moon_repomix.Style::Xml)
  assert_true(defaults.security_check)
  assert_eq(defaults.max_files, 20000)
  assert_eq(defaults.max_total_size, 209715200L)
  assert_false(defaults.full_metadata)
  assert_true(
    defaults.file_summary &&
    defaults.directory_structure &&
    defaults.include_files,
  )
  assert_true(defaults.git_sections && defaults.metadata)
  assert_false(defaults.show_line_numbers)
  assert_eq(
    defaults.output_file_path_style,
    @moon_repomix.PathStyle::TargetRelative,
  )
  assert_eq(defaults.file_paths, None)
  assert_eq(defaults.keep_full_patterns, [])
  assert_eq(defaults.header_text, "")
  assert_eq(defaults.instruction_file_path, None)
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
  let zero = @moon_repomix.options(".", max_files=0, max_total_size=0L)
  assert_eq(zero.max_files, 0)
  assert_eq(zero.max_total_size, 0L)
  for (count, total) in [(-1, 0L), (0, -1L), (0, 9007199254740992L)] {
    try
      @moon_repomix.options(".", max_files=count, max_total_size=total)
    catch {
      @config.ConfigError::InvalidValue(field) =>
        assert_true(field == "input.maxFiles" || field == "input.maxTotalSize")
      _ => fail("unexpected options error")
    } noraise {
      _ => fail("invalid SDK resource limits must fail")
    }
  }
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
