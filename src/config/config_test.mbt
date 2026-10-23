///|
test "defaults and presence-aware configuration precedence" {
  let cli = @config.parse_cli([])
  assert_eq(cli.directory, ".")
  assert_eq(cli.config_path, None)
  assert_eq(cli.action, @config.Action::Pack)
  assert_eq(cli.patch.security_check, None)
  assert_eq(cli.stdin_mode, @config.StdinMode::Off)
  let defaults = @config.resolve(cli, None)
  assert_eq(defaults.output, "repomix-output.xml")
  assert_eq(defaults.style, @config.Style::Xml)
  assert_eq(defaults.encoding, "o200k_base")
  assert_true(defaults.security_check)
  assert_eq(defaults.max_file_size, 52428800)
  assert_eq(defaults.token_budget, None)
  assert_eq(defaults.top_files_length, 5)
  assert_false(defaults.full_metadata)
  assert_eq(defaults.keep_full_patterns, [])
  assert_eq(defaults.file_paths, None)
  let mixed = @config.parse_json(
    "{\"output\":{\"compress\":true,\"keepFull\":[\"README.md\",\"src/core/**\"]}}",
  )
  let mixed_options = @config.resolve(
    @config.parse_cli(["--keep-full=src/core/**,src/*.{mbt,ts}"]),
    Some(mixed),
  )
  assert_true(mixed_options.compress)
  assert_eq(mixed_options.keep_full_patterns, [
    "README.md", "src/core/**", "src/*.{mbt,ts}",
  ])
  assert_eq(mixed.keep_full_patterns, ["README.md", "src/core/**"])
  let templates = @config.parse_json(
    "{\"output\":{\"headerText\":\"config header\",\"instructionFilePath\":\"notes.md\"}}",
  )
  let configured = @config.resolve(@config.parse_cli([]), Some(templates))
  assert_eq(configured.header_text, "config header")
  assert_eq(configured.instruction_file_path, Some("notes.md"))
  let cleared = @config.resolve(
    @config.parse_cli(["--header-text=", "--instruction-file-path="]),
    Some(templates),
  )
  assert_eq(cleared.header_text, "")
  assert_eq(cleared.instruction_file_path, None)
  let overridden = @config.resolve(
    @config.parse_cli([
      "--header-text", "命令行\r\nheader", "--instruction-file-path=other.md",
    ]),
    Some(templates),
  )
  assert_eq(overridden.header_text, "命令行\r\nheader")
  assert_eq(overridden.instruction_file_path, Some("other.md"))
  assert_eq(templates.instruction_file_path, Some("notes.md"))
  assert_false(
    @config.resolve(@config.parse_cli(["--no-compress"]), Some(mixed)).compress,
  )
  let detailed = @config.parse_json("{\"output\":{\"fullMetadata\":true}}")
  assert_true(
    @config.resolve(@config.parse_cli([]), Some(detailed)).full_metadata,
  )
  assert_false(
    @config.resolve(@config.parse_cli(["--no-full-metadata"]), Some(detailed)).full_metadata,
  )
  assert_true(
    @config.resolve(@config.parse_cli(["--full-metadata"]), None).full_metadata,
  )
  assert_eq(defaults.token_count_tree, @config.TokenCountTree::Disabled)
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
test "all output styles resolve from CLI and JSON with matching default names" {
  for
    (name, style, suffix) in [
      ("xml", @config.Style::Xml, "xml"),
      ("markdown", @config.Style::Markdown, "md"),
      ("json", @config.Style::Json, "json"),
      ("plain", @config.Style::Plain, "txt"),
    ] {
    let cli = @config.resolve(@config.parse_cli(["--style=" + name]), None)
    assert_eq(cli.style, style)
    assert_eq(cli.output, "repomix-output." + suffix)
    let file = @config.parse_json("{\"output\":{\"style\":\"" + name + "\"}}")
    let configured = @config.resolve(@config.parse_cli([]), Some(file))
    assert_eq(configured.style, style)
    assert_eq(configured.output, cli.output)
    let explicit = @config.resolve(
      @config.parse_cli(["--style=" + name, "-o", "custom.data"]),
      Some(file),
    )
    assert_eq(explicit.output, "custom.data")
  }
  let file = @config.parse_json(
    "{\"output\":{\"style\":\"json\",\"filePath\":\"configured.data\"}}",
  )
  let overridden = @config.resolve(
    @config.parse_cli(["--style=plain"]),
    Some(file),
  )
  assert_eq(overridden.style, @config.Style::Plain)
  assert_eq(overridden.output, "configured.data")
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
  for args in [["-o", "-"], ["--output=-"], ["--stdout", "--output", "-"]] {
    assert_true(@config.resolve(@config.parse_cli(args), None).stdout)
  }
  assert_true(
    @config.resolve(
      @config.parse_cli([]),
      Some(@config.parse_json("{\"output\":{\"filePath\":\"-\"}}")),
    ).stdout,
  )
  assert_false(
    @config.resolve(@config.parse_cli(["-o", "-", "-o", "./-"]), None).stdout,
  )
  assert_eq(@config.parse_cli(["--stdin"]).stdin_mode, @config.StdinMode::Lines)
  assert_eq(
    @config.parse_cli(["--stdin0", "--stdin0"]).stdin_mode,
    @config.StdinMode::Nul,
  )
  assert_eq(
    @config.parse_cli([
      "--include=src/*.{js,ts},docs/{a,{b,c}}.md,icons/[,].svg",
    ]).patch.include_patterns,
    ["src/*.{js,ts}", "docs/{a,{b,c}}.md", "icons/[,].svg"],
  )
}

///|
test "literal file-list protocols preserve names and explicit emptiness" {
  assert_eq(
    @config.parse_file_list("\uFEFFsrc/a.ts\r\n spaced name.js \r\n\n"),
    ["src/a.ts", " spaced name.js "],
  )
  assert_eq(@config.parse_file_list("a\nb.ts\u0000 leading \u0000", nul=true), [
    "a\nb.ts", " leading ",
  ])
  assert_eq(@config.parse_file_list(""), [])
  assert_eq(@config.parse_file_list("\r\n\n"), [])
  try @config.parse_file_list("a\u0000b\n") catch {
    @config.ConfigError::InvalidValue("stdin") => ()
    _ => fail("unexpected file-list error")
  } noraise {
    _ => fail("NUL is not a newline list separator")
  }
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
        #|{"output":{"style":"html"}}
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
        #|{"output":{"compress":1}}
      ),
      (
        #|{"output":{"keepFull":[false]}}
      ),
      (
        #|{"output":{"headerText":false}}
      ),
      (
        #|{"output":{"instructionFilePath":[]}}
      ),
      (
        #|{"output":{"instructionFilePath":"bad\u0000path"}}
      ),
      (
        #|{"output":{"keepFull":["../escape"]}}
      ),
      (
        #|{"output":{"fullMetadata":"true"}}
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
      ["--include-logs-count=0"],
      ["--include-logs-count=10001"],
      ["--max-git-bytes=0"],
      ["--quiet", "--verbose"],
      ["--stdout", "-o", "out.xml"],
      ["--stdin", "--stdin0"],
      ["--stdin0", "--stdin"],
      ["--stdin=false"],
      ["--stdin0=false"],
      ["--init", "--stdin"],
      ["--include=src/{a,b"],
      ["--output"],
      ["--style=html"],
      ["one", "two"],
      ["--token-budget=0"],
      ["--token-budget=-2"],
      ["--token-budget=1.5"],
      ["--token-budget=2147483648"],
      ["--no-security-check=false"],
      ["--full-metadata=false"],
      ["--init", "--version"],
      ["--tokenizer-path="],
      ["--top-files-len"],
      ["--top-files-len=-1"],
      ["--top-files-len=1.5"],
      ["--top-files-len=2147483648"],
      ["--token-count-tree="],
      ["--token-count-tree=-1"],
      ["--token-count-tree", "invalid"],
      ["--token-count-tree=1.5"],
      ["--token-count-tree=2147483648"],
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
  for pattern in ["/absolute", "a/../b", "../b", "C:/data", "a\\b", "!keep", ""] {
    try @config.parse_cli(["--include=" + pattern]) catch {
      @config.ConfigError::InvalidValue("glob") => ()
      _ => fail("expected glob error")
    } noraise {
      _ => fail("expected invalid glob")
    }
  }
}

///|
test "token report configuration, optional threshold and explicit overrides" {
  let file = @config.parse_json(
    (
      #|{"output":{"topFilesLength":2,"tokenCountTree":true}}
    ),
  )
  let configured = @config.resolve(@config.parse_cli([]), Some(file))
  assert_eq(configured.top_files_length, 2)
  assert_eq(configured.token_count_tree, @config.TokenCountTree::Enabled(0))
  let overridden = @config.resolve(
    @config.parse_cli(["repo", "--top-files-len=0", "--token-count-tree", "7"]),
    Some(file),
  )
  assert_eq(overridden.top_files_length, 0)
  assert_eq(overridden.token_count_tree, @config.TokenCountTree::Enabled(7))
  for
    args in [
      ["repo", "--token-count-tree"],
      ["--token-count-tree", "--", "repo"],
      ["--token-count-tree=0", "repo"],
    ] {
    let options = @config.resolve(@config.parse_cli(args), None)
    assert_eq(options.directory, "repo")
    assert_eq(options.token_count_tree, @config.TokenCountTree::Enabled(0))
  }
  for
    (value, expected) in [
      ("false", @config.TokenCountTree::Disabled),
      ("true", @config.TokenCountTree::Enabled(0)),
      ("0", @config.TokenCountTree::Enabled(0)),
      ("12", @config.TokenCountTree::Enabled(12)),
      ("\"12\"", @config.TokenCountTree::Enabled(12)),
    ] {
    let json = @config.parse_json(
      "{\"output\":{\"tokenCountTree\":" + value + "}}",
    )
    assert_eq(
      @config.resolve(@config.parse_cli([]), Some(json)).token_count_tree,
      expected,
    )
  }
  let explicit = @config.Patch::empty()
  explicit.token_count_tree = Some(@config.TokenCountTree::Disabled)
  let base = @config.parse_cli([])
  assert_eq(
    @config.resolve({ ..base, patch: explicit, }, Some(file)).token_count_tree,
    @config.TokenCountTree::Disabled,
  )
  for field in ["topFilesLength", "tokenCountTree"] {
    for value in ["-1", "1.5", "2147483648", "null", "[]", "\"invalid\""] {
      try
        @config.parse_json("{\"output\":{\"" + field + "\":" + value + "}}")
      catch {
        @config.ConfigError::InvalidValue(actual) =>
          assert_eq(actual, "output." + field)
        _ => fail("unexpected token report error")
      } noraise {
        _ => fail("expected invalid token report field")
      }
    }
  }
  for field in ["topFilesLength", "tokenCountTree"] {
    let invalid = @config.Patch::empty()
    if field == "topFilesLength" {
      invalid.top_files_length = Some(-1)
    } else {
      invalid.token_count_tree = Some(@config.TokenCountTree::Enabled(-1))
    }
    try @config.resolve({ ..base, patch: invalid, }, None) catch {
      @config.ConfigError::InvalidValue(actual) =>
        assert_eq(actual, "output." + field)
      _ => fail("unexpected patch error")
    } noraise {
      _ => fail("expected invalid report patch")
    }
  }
}
