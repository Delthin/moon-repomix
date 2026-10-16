///|
test "defaults and presence-aware configuration precedence" {
  let cli = @config.parse_cli([])
  assert_eq(cli.directory, ".")
  assert_eq(cli.config_path, None)
  assert_eq(cli.action, @config.Action::Pack)
  assert_eq(cli.patch.security_check, None)
  let defaults = @config.resolve(cli, None)
  assert_eq(defaults.output, "repomix-output.xml")
  assert_eq(defaults.style, @config.Style::Xml)
  assert_eq(defaults.encoding, "o200k_base")
  assert_true(defaults.security_check)
  assert_eq(defaults.max_file_size, 52428800)
  assert_eq(defaults.token_budget, None)
  let file = @config.parse_json(
    (
      #|{"include":["src/**","src/**"],"ignore":{"customPatterns":["tmp/**"],"useGitignore":false,"useDotIgnore":false,"useDefaultPatterns":false},"security":{"enableSecurityCheck":false},"output":{"style":"markdown","tokenBudget":200},"input":{"maxFileSize":1024},"tokenCount":{"encoding":"o200k_base"}}
    ),
  )
  let merged = @config.resolve(
    @config.parse_cli([
      "repo", "--include", "src/**, docs/**", "-i", "tmp/**,cache/**", "--token-budget=300",
      "--tokenizer-path", "./assets/o200k_base.tiktoken", "-c", "./custom.json",
    ]),
    Some(file),
  )
  assert_eq(merged.output, "repomix-output.md")
  assert_eq(merged.include_patterns, ["src/**", "docs/**"])
  assert_eq(merged.ignore, ["tmp/**", "cache/**"])
  assert_false(merged.security_check)
  assert_false(merged.use_gitignore)
  assert_false(merged.use_dot_ignore)
  assert_false(merged.use_default_patterns)
  assert_eq(merged.max_file_size, 1024)
  assert_eq(merged.token_budget, Some(300))
  assert_eq(merged.tokenizer_path, Some("./assets/o200k_base.tiktoken"))
  // The CLI must not mutate JSON lists while appending or deduplicating them.
  assert_eq(file.include_patterns, ["src/**", "src/**"])
  let explicit = @config.Patch::empty()
  explicit.security_check = Some(true)
  let base = @config.parse_cli([])
  let overrides : @config.Cli = { ..base, patch: explicit, }
  assert_true(@config.resolve(overrides, Some(file)).security_check)
}

///|
test "CLI surface and action queries are pure" {
  let cli = @config.parse_cli([
    "--style=markdown", "--stdout", "--no-gitignore", "--no-dot-ignore", "--no-default-patterns",
    "--no-security-check", "--token-count-encoding", "o200k_base", "--quiet", "--parsable-style",
    "--config=relative.json", "--", "-repo",
  ])
  assert_eq(cli.directory, "-repo")
  assert_eq(cli.config_path, Some("relative.json"))
  assert_true(cli.stdout)
  assert_eq(cli.patch.security_check, Some(false))
  assert_true(@config.resolve(cli, None).quiet)
  for
    (arg, expected) in [
      ("--help", @config.Action::Help),
      ("-h", @config.Action::Help),
      ("--version", @config.Action::Version),
      ("-v", @config.Action::Version),
      ("--init", @config.Action::Init),
    ] {
    assert_eq(@config.parse_cli([arg]).action, expected)
  }
  let explicit = @config.resolve(
    @config.parse_cli(["--output=out.txt", "--style=markdown", "--verbose"]),
    None,
  )
  assert_eq(explicit.output, "out.txt")
  assert_true(explicit.verbose)
  // --stdout conflicts with explicit CLI output, not a configured default filename.
  let stdout = @config.resolve(
    @config.parse_cli(["--stdout"]),
    Some(
      @config.parse_json(
        (
          #|{"output":{"filePath":"configured.xml"}}
        ),
      ),
    ),
  )
  assert_true(stdout.stdout)
}

///|
test "strict rejection of invalid configuration and CLI" {
  for
    text in [
      "[]",
      "null",
      "{",
      "{\"remote\":true}",
      (
        #|{"output":{"filePath":null}}
      ),
      (
        #|{"output":{"style":"plain"}}
      ),
      (
        #|{"output":{"tokenBudget":0}}
      ),
      (
        #|{"output":{"tokenBudget":1.5}}
      ),
      (
        #|{"input":{"maxFileSize":-1}}
      ),
      (
        #|{"input":{"maxFileSize":2147483648}}
      ),
      (
        #|{"ignore":{"useGitignore":"false"}}
      ),
      (
        #|{"ignore":{"customPatterns":["!keep"]}}
      ),
      (
        #|{"tokenCount":{"encoding":"cl100k_base"}}
      ),
      (
        #|{"security":{"unrecognized":false}}
      ),
      (
        #|{"output":{"compress":true}}
      ),
      (
        #|{"include":[false]}
      ),
    ] {
    try @config.parse_json(text) catch {
      @config.ConfigError::InvalidJson
      | @config.ConfigError::UnknownField(_)
      | @config.ConfigError::InvalidValue(_) => ()
      _ => fail("unexpected error type")
    } noraise {
      _ => fail("expected invalid JSON configuration")
    }
  }
  for
    args in [
      ["--remote"],
      ["--quiet", "--verbose"],
      ["--stdout", "-o", "out.xml"],
      ["--output"],
      ["--style=json"],
      ["one", "two"],
      ["--token-budget=0"],
      ["--token-budget=-2"],
      ["--token-budget=1.5"],
      ["--token-budget=2147483648"],
      ["--no-security-check=false"],
      ["--init", "--version"],
      ["--tokenizer-path="],
    ] {
    try @config.parse_cli(args) catch {
      @config.ConfigError::UnknownOption(_)
      | @config.ConfigError::MissingValue(_)
      | @config.ConfigError::Conflict(_)
      | @config.ConfigError::MultipleDirectories
      | @config.ConfigError::InvalidValue(_) => ()
      _ => fail("unexpected error type")
    } noraise {
      _ => fail("expected invalid CLI arguments")
    }
  }
  for
    pattern in [
      "{a,b}", "/absolute", "a/../b", "../b", "C:/data", "a\\b", "!keep", "",
    ] {
    try @config.parse_cli(["--include=" + pattern]) catch {
      @config.ConfigError::InvalidValue("glob") => ()
      _ => fail("expected glob error")
    } noraise {
      _ => fail("expected invalid glob")
    }
  }
}
