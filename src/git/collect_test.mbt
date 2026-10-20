///|
async fn fixture_git(directory : String, args : Array[String]) -> Unit {
  let null = if @platform.is_windows() { "NUL" } else { "/dev/null" }
  let argv = [
    "-c",
    "user.name=Fixture",
    "-c",
    "user.email=fixture@example.invalid",
    "-c",
    "commit.gpgSign=false",
    "-c",
    "core.hooksPath=" + null,
    "-C",
    directory,
  ]
  argv.append(args)
  let environment = { "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": null }
  for
    key in ["PATH", "SystemRoot", "WINDIR", "TEMP", "TMP", "TMPDIR", "PATHEXT"] {
    if @env.get_env_var(key) is Some(value) {
      environment[key] = value
    }
  }
  let (code, _, _) = @process.collect_output(
    "git",
    argv,
    inherit_env=false,
    extra_env=environment,
  )
  assert_eq(code, 0)
}

///|
async test "real repository: unborn, scoped patches, NUL names, logs and unsafe extensions" {
  let dir = @fs.tmpdir(prefix="moon-git-context-test-")
  defer @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
  fixture_git(dir, ["init", "--template=", "--initial-branch=main"])
  @fs.mkdir(dir + "/scope")
  let odd = if @platform.is_windows() {
    "- odd 文件 [x].txt"
  } else {
    "- odd\t\n文件 | [x]*.txt"
  }
  for name in ["keep", "delete", "old", "cross", odd] {
    @fs.write_file(
      dir + "/scope/" + name,
      "original " + name + "\n",
      create_mode=CreateOrTruncate,
    )
  }
  @fs.write_file(dir + "/outside", "outside\n", create_mode=CreateOrTruncate)
  fixture_git(dir, ["add", "--", "."])
  let unborn = @git.collect(dir + "/scope", diffs=true, logs=2)
  assert_true(unborn.revision is None)
  assert_eq(unborn.diffs.length(), 5)
  assert_eq(unborn.commits.length(), 0)
  fixture_git(dir, [
    "commit", "-m", "initial | subject", "-m", "body\nsecond line",
  ])
  @fs.write_file(dir + "/scope/keep", "staged value\n")
  fixture_git(dir, ["add", "--", "scope/keep"])
  @fs.write_file(dir + "/scope/keep", "unstaged value\n")
  @fs.remove(dir + "/scope/delete")
  fixture_git(dir, ["mv", "--", "scope/old", "scope/new"])
  fixture_git(dir, ["mv", "--", "scope/cross", "outside-moved"])
  @fs.write_file(dir + "/scope/" + odd, "special changed\n")
  @fs.write_file(dir + "/outside", "outside changed\n")
  let marker = dir + "/extension-ran"
  // Deliberately executable repository configuration. The trailing comment
  // ignores Git's extension arguments. This is fixture data, never a runner.
  let attack = if @platform.is_windows() {
    "cmd.exe /d /c exit 99"
  } else {
    "/usr/bin/touch '" + marker + "' #"
  }
  fixture_git(dir, ["config", "core.fsmonitor", attack])
  if !@platform.is_windows() {
    fixture_git(dir, ["status", "--porcelain"])
    assert_true(@fs.exists(marker))
    @fs.remove(marker)
  }
  fixture_git(dir, ["config", "diff.external", attack])
  fixture_git(dir, ["config", "diff.hostile.textconv", attack])
  fixture_git(dir, ["config", "filter.hostile.clean", attack])
  fixture_git(dir, ["config", "filter.hostile.process", attack])
  fixture_git(dir, ["config", "filter.hostile.required", "true"])
  fixture_git(dir, ["config", "log.showSignature", "true"])
  @fs.write_file(
    dir + "/scope/.gitattributes",
    "keep diff=hostile filter=hostile\n",
    create_mode=CreateOrTruncate,
  )
  let snapshot = @git.collect(dir + "/scope", diffs=true, logs=2)
  assert_false(@fs.exists(marker))
  assert_eq(snapshot.repository_root, @platform.separators(@fs.realpath(dir)))
  assert_true(snapshot.revision is Some(_))
  assert_eq(snapshot.diffs.length(), 6)
  let staged = snapshot.diffs.filter(d => d.kind == "staged")
  let unstaged = snapshot.diffs.filter(d => d.kind == "unstaged")
  assert_eq(staged.length(), 3)
  assert_eq(unstaged.length(), 3)
  let rename = staged.filter(d => d.paths.contains("old"))
  assert_eq(rename.length(), 1)
  assert_eq(rename[0].paths, ["old", "new"])
  assert_true(rename[0].text.contains("rename from old"))
  assert_true(
    staged.any(d => d.paths == ["cross"] && d.text.contains("deleted file")),
  )
  assert_true(
    staged.any(d => d.paths == ["keep"] && d.text.contains("+staged value")),
  )
  assert_true(
    unstaged.any(d => d.paths == ["keep"] && d.text.contains("+unstaged value")),
  )
  assert_true(
    unstaged.any(d => d.paths == ["delete"] && d.text.contains("deleted file")),
  )
  assert_true(
    unstaged.any(d => d.paths == [odd] && d.text.contains("+special changed")),
  )
  for diff in snapshot.diffs {
    assert_false(diff.text.contains("outside changed"))
    assert_false(diff.text.contains("scope/"))
  }
  assert_eq(snapshot.commits.length(), 1)
  let commit = snapshot.commits[0]
  assert_eq(Some(commit.id), snapshot.revision)
  assert_true(commit.date.contains("T"))
  assert_eq(commit.message, "initial | subject\n\nbody\nsecond line\n")
  assert_eq(commit.files.length(), 5)
  assert_true(commit.files.contains(odd))
  assert_false(commit.files.contains("outside"))
  let root = @git.collect(dir, diffs=true, logs=1)
  assert_true(root.diffs.any(d => d.paths == ["scope/cross", "outside-moved"]))
  assert_true(root.commits[0].files.contains("scope/" + odd))
  assert_false(@fs.exists(marker))
  fixture_git(dir, ["config", "--unset", "core.fsmonitor"])
  fixture_git(dir, ["config", "--remove-section", "filter.hostile"])
  fixture_git(dir, ["commit", "-m", "rename and staged changes"])
  let history = @git.collect(dir + "/scope", logs=2)
  assert_eq(history.commits.length(), 2)
  assert_eq(history.commits[0].message, "rename and staged changes\n")
  assert_eq(history.commits[0].files.length(), 4)
  for path in ["keep", "old", "new", "cross"] {
    assert_true(history.commits[0].files.contains(path))
  }
  assert_eq(history.commits[1].id, commit.id)
  assert_false(@fs.exists(marker))
  try @git.collect(dir, diffs=true, max_bytes=100) catch {
    @git.OutputLimit => ()
    err => raise err
  } noraise {
    _ => fail("expected output cap error")
  }
  let plain = @fs.tmpdir(prefix="moon-git-not-repo-")
  defer @async.protect_from_cancel(() => @fs.rmdir(plain, recursive=true))
  try @git.collect(plain) catch {
    @git.NotRepository => ()
    err => raise err
  } noraise {
    _ => fail("expected not-a-repository error")
  }
}
