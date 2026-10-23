///|
fn assert_origin(
  decision : PathDecision,
  kind : String,
  source : String?,
  line : Int32?,
  index : Int32?,
) -> Unit raise {
  guard decision.origin is Some(origin) else {
    fail("expected origin for " + decision.path)
  }
  assert_eq(
    (origin.kind, origin.source, origin.line, origin.index),
    (kind, source, line, index),
  )
}

///|
async test "explain shares exact selection, layered decisions, literal spelling and host membership" {
  fixture() <| root => {
    init_git(root)
    put(root, ".git/info/exclude", "# metadata\ninfo.txt\n")
    put(root, ".gitignore", "# rules\ngit.txt\npruned/\nsame.txt\n")
    put(root, ".ignore", "# rules\ndot.txt\n!same.txt\n")
    put(root, ".repomixignore", "# rules\nrepomix.txt\n!revived/\n")
    put(root, "src/.repomixignore", "# nested\nnested.txt\n")
    put(root, "pruned/.repomixignore", "[invalid\n")
    put(root, "unrelated/.repomixignore", "[invalid\n")
    let literal = literal_glob_filename()
    let paths = [
      "src/keep.txt", "src/nested.txt", "same.txt", "node_modules/pkg/a.txt", "custom.txt",
      "git.txt", "dot.txt", "repomix.txt", "info.txt", "pruned/a.txt", "not-included.txt",
      "output.txt", literal, "猫.txt", "\u{e000}.txt", "\u{10000}.txt",
    ]
    for path in paths {
      put(root, path, "not opened or scanned")
    }
    let queries = paths.copy()
    queries.append(["missing.txt", "src", "src/keep.txt"])
    let options = {
      ..SelectionOptions::default(),
      include_patterns: ["*.txt", "src"],
      ignore: ["{unused,custom}.txt", "not-included-never"],
      output: Some(join(root, "output.txt")),
    }
    let result = explain(root, options, queries)
    let selected = select(root, options, file_paths=Some(queries))
    assert_eq(result.selection.root, selected.root)
    assert_eq(
      result.selection.files.map(f => (f.path, f.relative)),
      selected.files.map(f => (f.path, f.relative)),
    )
    assert_eq(
      result.selection.skipped.map(s => (s.path, s.reason)),
      selected.skipped.map(s => (s.path, s.reason)),
    )
    assert_eq(
      result.decisions.map(d => d.path),
      exact_paths(Some(queries)).unwrap(),
    )
    assert_eq(result.decisions.filter(d => d.eligible).map(d => d.path), [
      literal, "not-included.txt", "same.txt", "src/keep.txt", "猫.txt", "\u{e000}.txt",
      "\u{10000}.txt",
    ])
    assert_true(
      result.decisions
      .filter(d => d.eligible)
      .all(d => d.reason == "Candidate" && d.origin is None),
    )
    let decisions = Map::from_array(result.decisions.map(d => (d.path, d)))
    assert_eq(decisions["src"].reason, "Directory")
    assert_eq(decisions["missing.txt"].reason, "MissingFile")
    assert_eq(decisions["output.txt"].reason, "OutputFile")
    assert_eq(decisions["pruned/a.txt"].reason, "IgnoredDirectory")
    assert_eq(decisions["git.txt"].reason, "Ignored")
    assert_origin(decisions["custom.txt"], "custom", None, None, Some(1))
    assert_origin(
      decisions["git.txt"],
      "gitignore",
      Some(".gitignore"),
      Some(2),
      None,
    )
    assert_origin(
      decisions["dot.txt"],
      "dot-ignore",
      Some(".ignore"),
      Some(2),
      None,
    )
    assert_origin(
      decisions["repomix.txt"],
      "repomixignore",
      Some(".repomixignore"),
      Some(2),
      None,
    )
    assert_origin(
      decisions["src/nested.txt"],
      "repomixignore",
      Some("src/.repomixignore"),
      Some(2),
      None,
    )
    assert_origin(
      decisions["pruned/a.txt"],
      "gitignore",
      Some(".gitignore"),
      Some(3),
      None,
    )
    assert_origin(
      decisions["info.txt"],
      "git-info-exclude",
      Some(".git/info/exclude"),
      Some(2),
      None,
    )
    guard decisions["node_modules/pkg/a.txt"].origin is Some(default_origin) else {
      fail("missing default origin")
    }
    assert_eq(default_origin.kind, "default")
    assert_true(default_origin.index is Some(_))
    assert_eq(default_origin.source, None)
    for decision in result.decisions {
      assert_false(decision.reason.contains(root))
      assert_false(decision.reason.contains("*.txt"))
      if decision.origin is Some(origin) && origin.source is Some(source) {
        assert_true(relative_file_path(source))
        assert_false(source.contains(root))
      }
    }
    // Host membership is independent of the query set and wins before rule I/O.
    let host = explain(
      root,
      options,
      ["src/keep.txt", "unrelated/hidden.txt", "missing.txt"],
      file_paths=Some(["src/keep.txt"]),
    )
    assert_eq(host.decisions.map(d => (d.path, d.reason)), [
      ("missing.txt", "NotListed"),
      ("src/keep.txt", "Candidate"),
      ("unrelated/hidden.txt", "NotListed"),
    ])
    assert_eq(host.selection.files.map(f => f.relative), ["src/keep.txt"])
    let empty_host = explain(
      root,
      options,
      ["src/keep.txt"],
      file_paths=Some([]),
      max_files=0,
    )
    assert_eq(empty_host.decisions[0].reason, "NotListed")
    let empty_query = explain(root, options, [], max_files=0)
    assert_eq(empty_query.decisions.length(), 0)
    assert_eq(empty_query.selection.files.length(), 0)
    let not_included = explain(
      root,
      { ..options, include_patterns: ["src"], },
      ["not-included.txt"],
    )
    assert_eq(not_included.decisions[0].reason, "NotIncluded")
    let limited = explain(
      root,
      options,
      ["git.txt", "src/keep.txt"],
      max_files=1,
    )
    assert_eq(limited.selection.files.length(), 1)
    for limit in [-1, 0, 1] {
      try
        explain(root, options, ["src/keep.txt", "same.txt"], max_files=limit)
      catch {
        SelectionError::FileLimitExceeded(limit=actual) =>
          assert_eq(actual, limit)
        e => raise e
      } noraise {
        _ => fail("expected candidate limit failure")
      }
    }
    // Exact queries enforce raw names even without a host file_paths list.
    let alias_reason = if optional_kind(join(root, "SRC/keep.txt"))
      is Some(Regular) {
      "NonLiteralPath"
    } else {
      "MissingFile"
    }
    let aliased = explain(root, options, ["SRC/keep.txt"])
    assert_eq(aliased.decisions[0].reason, alias_reason)
    assert_false(aliased.decisions[0].eligible)
    let filter = path_filter(root, options, file_paths=Some(queries))
    assert_true(filter.allows("missing.txt")) // Git deletions remain valid.
    assert_eq(
      filter.reason("pruned/a.txt", true),
      Some("IgnoredDirectory:" + join(root, ".gitignore") + ":3"),
    )
    assert_false(filter.cache.contains(join(root, "pruned")))
    assert_false(filter.names.contains(join(root, "pruned")))
  }
}

///|
async test "explain safe ancestor and external origins, fatal validation and no-follow" {
  fixture() <| directory => {
    init_git(directory)
    put(directory, ".gitignore", "# ancestor\nroot/parent.txt\nroot/blocked/\n")
    let root = join(directory, "root")
    put(root, "parent.txt", "body")
    put(root, "blocked/child.txt", "body")
    put(root, "blocked/.repomixignore", "[invalid\n")
    let options = SelectionOptions::default()
    let inherited = explain(root, options, ["parent.txt", "blocked/child.txt"])
    assert_eq(inherited.decisions.map(d => (d.path, d.reason)), [
      ("blocked/child.txt", "IgnoredDirectory"),
      ("parent.txt", "Ignored"),
    ])
    assert_origin(inherited.decisions[0], "gitignore", None, Some(3), None)
    assert_origin(inherited.decisions[1], "gitignore", None, Some(2), None)
    let blocked = explain(join(root, "blocked"), options, ["child.txt"])
    assert_eq(blocked.decisions[0].reason, "IgnoredDirectory")
    assert_origin(blocked.decisions[0], "gitignore", None, Some(3), None)
    // Synthetic linked-worktree metadata outside the selected root.
    put(directory, "main/.git/info/exclude", "# external\nfrom-info.txt\n")
    put(directory, "main/.git/worktrees/linked/commondir", "../..\n")
    put(directory, "linked/.git", "gitdir: ../main/.git/worktrees/linked\n")
    put(directory, "linked/from-info.txt", "body")
    let external = explain(join(directory, "linked"), options, ["from-info.txt"])
    assert_eq(external.decisions[0].reason, "Ignored")
    assert_origin(
      external.decisions[0],
      "git-info-exclude",
      None,
      Some(2),
      None,
    )
    assert_false(external.decisions[0].reason.contains(directory))
    // Invalid queries and host lists fail the whole call before malformed rules.
    put(root, ".repomixignore", "[invalid\n")
    for
      invalid in [
        "", "/absolute", "../escape", "a/../b", "a/./b", "a//b", "a/", "a\u{0}b",
        "a\\b", "C:relative",
      ] {
      for host_invalid in [false, true] {
        try {
          if host_invalid {
            ignore(
              explain(root, options, ["parent.txt"], file_paths=Some([invalid])),
            )
          } else {
            ignore(explain(root, options, ["parent.txt", invalid]))
          }
        } catch {
          SelectionError::InvalidPattern(source~, line~, pattern~, ..) => {
            assert_eq(source, "file_paths")
            assert_eq(line, 0)
            assert_eq(pattern, invalid)
          }
          e => raise e
        } noraise {
          _ => fail("expected invalid exact path")
        }
      }
    }
    let empty = explain(root, options, [])
    assert_eq(empty.decisions.length(), 0) // No local rule read for empty queries.
    try explain(root, options, ["parent.txt"]) catch {
      SelectionError::InvalidPattern(source~, line~, ..) => {
        assert_eq(source, join(root, ".repomixignore"))
        assert_eq(line, 1)
      }
      e => raise e
    } noraise {
      _ => fail("malformed visited rules must propagate")
    }
    @fs.remove(join(root, ".repomixignore"))
    explain_nofollow(root, options)
  }
}

///|
#cfg(platform="windows")
fn explain_nofollow(_root : String, _options : SelectionOptions) -> Unit {
  // The symbolic-link and FIFO fixture below is POSIX-only.
}

///|
#cfg(not(platform="windows"))
async fn explain_nofollow(root : String, options : SelectionOptions) -> Unit {
  put(root, "safe/file.txt", "secret-looking content is not scanned here")
  put(root, "ordinary", "body")
  put(root, "outside/.repomixignore", "[invalid\n")
  @fs.symlink(target=join(root, "outside"), join(root, "linked"))
  @fs.symlink(target=join(root, "missing"), join(root, "broken"))
  @fs.symlink(target=join(root, "safe/file.txt"), join(root, "file-link"))
  let (code, _, error) = @process.collect_output("mkfifo", [join(root, "pipe")])
  assert_eq(code, 0, msg=error.text())
  @fs.chmod(join(root, "safe/file.txt"), 0)
  let result = @async.with_timeout(5000, () => {
    explain(root, options, [
      "linked/child.txt", "broken/child.txt", "file-link", "pipe", "ordinary/child",
      "safe/file.txt",
    ])
  })
  assert_eq(result.decisions.map(d => (d.path, d.reason)), [
    ("broken/child.txt", "Symlink"),
    ("file-link", "Symlink"),
    ("linked/child.txt", "Symlink"),
    ("ordinary/child", "NotDirectory"),
    ("pipe", "UnsupportedFileType"),
    ("safe/file.txt", "Candidate"),
  ])
  assert_eq(result.selection.files.map(f => f.relative), ["safe/file.txt"])
}
