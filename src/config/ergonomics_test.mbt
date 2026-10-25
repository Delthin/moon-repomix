///|
test "CLI shortcuts preserve precedence, validation and help-only actions" {
  for
    (args, style, output) in [
      (["-f", "md"], @config.Style::Markdown, "repomix-output.md"),
      (["--format=txt"], @config.Style::Plain, "repomix-output.txt"),
      (["--style=md"], @config.Style::Markdown, "repomix-output.md"),
      (["--format", "json"], @config.Style::Json, "repomix-output.json"),
      (["-f=md", "--style=xml"], @config.Style::Xml, "repomix-output.xml"),
      (
        ["--style=xml", "--format=markdown"],
        @config.Style::Markdown,
        "repomix-output.md",
      ),
    ] {
    let options = @config.resolve(@config.parse_cli(args), None)
    assert_eq(options.style, style)
    assert_eq(options.output, output)
  }
  let options = @config.resolve(
    @config.parse_cli(["--budget=300", "--token-budget", "400"]),
    Some(@config.parse_json("{\"output\":{\"tokenBudget\":200}}")),
  )
  assert_eq(options.token_budget, Some(400))
  let options = @config.resolve(
    @config.parse_cli(["--token-budget=300", "--budget", "400"]),
    None,
  )
  assert_eq(options.token_budget, Some(400))
  let options = @config.resolve(
    @config.parse_cli(["--split=300", "--split-output=400"]),
    None,
  )
  assert_eq(options.split_output, @config.SplitOutput::Enabled(400))
  assert_eq(options.output, "moon-repomix-output")
  let options = @config.resolve(
    @config.parse_cli(["--split-output=300", "--split=400", "-f", "md"]),
    None,
  )
  assert_eq(options.split_output, @config.SplitOutput::Enabled(400))
  assert_eq(options.style, @config.Style::Markdown)
  let options = @config.resolve(
    @config.parse_cli(["-f=txt"]),
    Some(@config.parse_json("{\"output\":{\"style\":\"json\"}}")),
  )
  assert_eq(options.style, @config.Style::Plain)
  // Output filenames do not select a format; explicit settings keep their meaning.
  assert_eq(
    @config.resolve(@config.parse_cli(["-o=context.md"]), None).style,
    @config.Style::Xml,
  )
  for value in ["md", "txt"] {
    try @config.parse_json("{\"output\":{\"style\":\"" + value + "\"}}") catch {
      _ => ()
    } noraise {
      _ => fail("CLI-only format shortcut was accepted in JSON")
    }
  }
  for args in [["--help-all"], ["--help", "--help-all"], ["--help-all", "-h"]] {
    assert_eq(@config.parse_cli(args).action, @config.Action::HelpAll)
  }
  for
    (args, action) in [
      (["--webui", "--help"], @config.Action::Help),
      (["--webui", "--help-all"], @config.Action::HelpAll),
      (["--webui", "--version"], @config.Action::Version),
    ] {
    assert_eq(@config.parse_cli(args).action, action)
  }
  for flag in ["-f", "--format", "--budget", "--split"] {
    try @config.parse_cli([flag]) catch {
      @config.ConfigError::MissingValue(value) => assert_eq(value, flag)
      _ => fail("expected missing-value error for the original option spelling")
    } noraise {
      _ => fail("missing option value was accepted")
    }
  }
  for
    args in [
      ["--format=html"],
      ["--budget=0"],
      ["--budget=-1"],
      ["--budget=1.5"],
      ["--split=0"],
      ["--split=2147483648"],
      ["--help-all=true"],
      ["--help-all", "--version"],
      ["--help-all", "--init"],
      ["--webui", "-f=md"],
      ["--webui", "--budget=400"],
      ["--webui", "--split=400"],
    ] {
    try @config.parse_cli(args) catch {
      _ => ()
    } noraise {
      _ =>
        fail("invalid CLI combination was accepted: " + Json(args).stringify())
    }
  }
  for args in [["--split=400", "--budget=300"], ["--split=400", "-o", "-"]] {
    try @config.resolve(@config.parse_cli(args), None) catch {
      _ => ()
    } noraise {
      _ => fail("split output conflict was accepted")
    }
  }
  let literal = @config.parse_cli(["--", "--format"])
  assert_eq(literal.directory, "--format")
  assert_eq(literal.patch.style, None)
}
