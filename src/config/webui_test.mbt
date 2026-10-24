///|
test "webui CLI has explicit constrained host authority" {
  let cli = @config.parse_cli(["workspace", "--webui"])
  assert_true(cli.webui)
  assert_eq(cli.directory, "workspace")
  assert_eq(cli.webui_port, 8765)
  let cli = @config.parse_cli([
    "--webui", "--webui-port=65535", "--max-files=2", "--max-total-size=40", "--max-file-size=20",
    "--tokenizer-path", "vocab",
  ])
  let options = @config.resolve(cli, None)
  assert_eq(cli.webui_port, 65535)
  assert_eq(options.max_files, 2)
  assert_eq(options.max_total_size, 40L)
  assert_eq(options.max_file_size, 20)
  assert_eq(options.tokenizer_path, Some("vocab"))
  assert_true(options.security_check)
  assert_eq(@config.parse_cli(["--webui", "--webui-port=1"]).webui_port, 1)
  for
    args in [
      ["--webui-port=8765"],
      ["--webui", "--webui-port=0"],
      ["--webui", "--webui-port=65536"],
      ["--webui", "--webui-port=-1"],
      ["--webui", "--webui-port=1.5"],
      ["--webui", "--config=x.json"],
      ["--webui", "--include=src/**"],
      ["--webui", "--ignore=src/**"],
      ["--webui", "--no-gitignore"],
      ["--webui", "--compress"],
      ["--webui", "--no-security-check"],
      ["--webui", "--stdout"],
      ["--webui", "--stdin"],
      ["--webui", "--mcp"],
      ["--webui", "--report-json"],
      ["--webui", "--init"],
      ["--webui", "--output=out.json"],
      ["--webui", "--remote=https://example.org/x"],
      ["--webui", "--quiet"],
      ["--webui", "--include-diffs"],
    ] {
    let rejected = try {
      ignore(@config.parse_cli(args))
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=Json(args).stringify())
  }
  let rejected = try {
    ignore(
      @config.resolve(
        @config.parse_cli(["--webui"]),
        Some(@config.Patch::empty()),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
