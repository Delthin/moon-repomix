///|
test "context transports resolve explicit output without pack redirection" {
  let file = Some(
    @config.parse_json(
      "{\"output\":{\"filePath\":\"pack.xml\",\"style\":\"json\"}}",
    ),
  )
  for args in [["--context-request=request.json"], ["--context-stdio"]] {
    let options = @config.resolve(@config.parse_cli(args), file)
    assert_eq(options.output, "-")
    assert_true(options.stdout)
    assert_eq(options.style, @config.Style::Json)
  }
  let cli = @config.parse_cli([
    "project", "--context-request", "req.json", "-o", "response.json", "--report-json",
  ])
  assert_eq(cli.context_request, Some("req.json"))
  assert_true(cli.report_json)
  let options = @config.resolve(cli, file)
  assert_eq(options.directory, "project")
  assert_eq(options.output, "response.json")
  assert_false(options.stdout)
}

///|
test "context transports reject explicit incompatible pack controls" {
  for
    extra in [
      ["--context-stdio"],
      ["--mcp"],
      ["--webui"],
      ["--stdin"],
      ["--stdin0"],
      ["--explain-path", "a"],
      ["--init"],
      ["--budget", "10"],
      ["--split", "10"],
      ["--remote", "https://example.com/repo.git"],
      ["--no-split-output"],
      ["--include-diffs"],
      ["--no-include-logs"],
      ["--top-files-len", "0"],
      ["--token-count-tree"],
      ["--parsable-style"],
      ["--no-files"],
      ["--webui-port", "9000"],
      ["--compress"],
      ["--no-compress"],
      ["--max-git-bytes", "100"],
    ] {
    let args = ["--context-request", "request.json"] + extra
    try @config.parse_cli(args) catch {
      _ => ()
    } noraise {
      _ => fail("context conflict accepted")
    }
  }
  for args in [["--context-stdio", "-o", "out"], ["--context-stdio", "-o", "-"]] {
    try @config.parse_cli(args) catch {
      _ => ()
    } noraise {
      _ => fail("stdio output accepted")
    }
  }
  for
    json in [
      "{\"output\":{\"tokenBudget\":10}}", "{\"output\":{\"splitOutput\":10}}", "{\"output\":{\"files\":false}}",
      "{\"output\":{\"compress\":true}}", "{\"input\":{\"maxGitBytes\":100}}", "{\"output\":{\"git\":{\"includeLogsCount\":10}}}",
    ] {
    let patch = @config.parse_json(json)
    try
      @config.resolve(@config.parse_cli(["--context-stdio"]), Some(patch))
    catch {
      @config.ConfigError::Conflict(_) => ()
      _ => fail("expected context configuration conflict")
    } noraise {
      _ => fail("inapplicable configuration accepted")
    }
  }
}
