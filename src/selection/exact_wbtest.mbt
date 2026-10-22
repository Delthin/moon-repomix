///|
async test "exact lists are literal, deduplicated and sorted, never recurse or scan unrelated trees" {
  fixture() <| root => {
    init_git(root)
    for
      path in [
        "z.txt", "literal[ab]*{x,y}.txt", " space .txt", "猫.txt", "src/child.txt",
        "unlisted.txt", "\u{e000}.txt", "\u{10000}.txt",
      ] {
      put(root, path, "body")
    }
    put(root, "unrelated/.repomixignore", "[invalid\n")
    let options = SelectionOptions::default()
    let paths = [
      "z.txt", "src", "literal[ab]*{x,y}.txt", "猫.txt", "z.txt", " space .txt",
      "\u{10000}.txt", "\u{e000}.txt",
    ]
    let result = select(root, options, file_paths=Some(paths))
    assert_eq(result.files.map(f => f.relative), [
      " space .txt", "literal[ab]*{x,y}.txt", "z.txt", "猫.txt", "\u{e000}.txt",
      "\u{10000}.txt",
    ])
    assert_eq(result.skipped.map(s => (s.path, s.reason)), [
      ("src", "Directory"),
    ])
    for file in result.files {
      assert_eq(file.path, join(result.root, file.relative))
    }
    let filter = path_filter(result.root, options, file_paths=Some(paths))
    assert_true(filter.allows("literal[ab]*{x,y}.txt"))
    assert_false(filter.allows("src"))
    assert_false(filter.allows("src/child.txt"))
    assert_false(filter.allows("unlisted.txt"))
    assert_false(filter.allows("unrelated/file.txt"))
    let empty = select(root, options, file_paths=Some([]))
    assert_eq(empty.files.length(), 0)
    assert_eq(empty.skipped.length(), 0)
    let no_paths = path_filter(root, options, file_paths=Some([]))
    assert_false(no_paths.allows("z.txt"))
    let normal = path_filter(root, options)
    assert_true(normal.allows("unlisted.txt"))
  }
}

///|
async test "exact lists share every exclusion layer, output precedence and Git deletion membership" {
  fixture() <| root => {
    init_git(root)
    put(root, ".gitignore", "git.txt\npruned/\n")
    put(root, ".ignore", "dot.txt\n")
    put(root, ".repomixignore", "repomix.txt\n")
    put(root, "src/.repomixignore", "nested.txt\n")
    put(root, "pruned/.repomixignore", "[invalid\n")
    for
      path in [
        "LICENSE", "nested/LICENSE", "src/keep.txt", "src/nested.txt", "custom.txt",
        "git.txt", "dot.txt", "repomix.txt", "node_modules/pkg/a.txt", "pruned/a.txt",
        ".env", "not-included.txt",
      ] {
      put(root, path, "body")
    }
    let paths = [
      "LICENSE", "nested/LICENSE", "src/keep.txt", "src/nested.txt", "custom.txt",
      "git.txt", "dot.txt", "repomix.txt", "node_modules/pkg/a.txt", "pruned/a.txt",
      ".env", "not-included.txt", "src/deleted.txt", "gone/deep/deleted.txt",
    ]
    let options = {
      ..SelectionOptions::default(),
      include_patterns: [
        "LICENSE", "src", "custom.txt", "git.txt", "dot.txt", "repomix.txt", "node_modules",
        "pruned", ".env", "gone",
      ],
      ignore: ["{custom,git}.txt", ".env"],
      output: Some(join(root, ".env")),
    }
    let result = select(root, options, file_paths=Some(paths))
    assert_eq(result.files.map(f => f.relative), ["LICENSE", "src/keep.txt"])
    assert_eq(result.skipped.map(s => (s.path, s.reason)), [
      (".env", "OutputFile"),
      ("custom.txt", "Ignored:custom"),
      ("dot.txt", "Ignored:" + join(root, ".ignore") + ":1"),
      ("git.txt", "Ignored:custom"),
      ("gone/deep/deleted.txt", "MissingFile"),
      ("nested/LICENSE", "NotIncluded"),
      ("node_modules/pkg/a.txt", "IgnoredDirectory:default"),
      ("not-included.txt", "NotIncluded"),
      ("pruned/a.txt", "IgnoredDirectory:" + join(root, ".gitignore") + ":2"),
      ("repomix.txt", "Ignored:" + join(root, ".repomixignore") + ":1"),
      ("src/deleted.txt", "MissingFile"),
      ("src/nested.txt", "Ignored:" + join(root, "src/.repomixignore") + ":1"),
    ])
    let filter = path_filter(root, options, file_paths=Some(paths))
    for path in paths {
      assert_eq(
        filter.allows(path),
        path == "LICENSE" ||
        path == "src/keep.txt" ||
        path == "src/deleted.txt" ||
        path == "gone/deep/deleted.txt",
        msg=path,
      )
    }
    assert_false(filter.allows("src/not-listed.txt"))
    let switches = select(
      root,
      {
        ..SelectionOptions::default(),
        use_default_patterns: false,
        use_gitignore: false,
        use_dot_ignore: false,
      },
      file_paths=Some([
        "dot.txt", "git.txt", "repomix.txt", "node_modules/pkg/a.txt",
      ]),
    )
    assert_eq(switches.files.map(f => f.relative), [
      "dot.txt", "git.txt", "node_modules/pkg/a.txt",
    ])
    assert_eq(switches.skipped[0].path, "repomix.txt")
    // The same inherited directory pruning applies when the selection root is blocked.
    let blocked = select(
      join(root, "pruned"),
      SelectionOptions::default(),
      file_paths=Some(["a.txt"]),
    )
    assert_eq(blocked.files.length(), 0)
    assert_eq(blocked.skipped.map(s => (s.path, s.reason)), [
      ("a.txt", "IgnoredDirectory:" + join(root, ".gitignore") + ":2"),
    ])
  }
}

///|
async test "invalid explicit paths fail both APIs as a whole before rule I/O" {
  fixture() <| root => {
    put(root, "good.txt", "body")
    put(root, ".repomixignore", "[invalid\n")
    let options = { ..SelectionOptions::default(), use_gitignore: false, }
    for
      path in [
        "", "/absolute", "//server/share/file", ".", "..", "../escape", "a/../b",
        "a/./b", "a//b", "a/", "a\u{0}b", "C:/absolute", "C:relative", "C:\\absolute",
        "\\\\server\\share", "\\rooted", "a\\..\\escape", "a:b",
      ] {
      try select(root, options, file_paths=Some(["good.txt", path])) catch {
        SelectionError::InvalidPattern(source~, line~, pattern~, ..) => {
          assert_eq(source, "file_paths")
          assert_eq(line, 0)
          assert_eq(pattern, path)
        }
        e => raise e
      } noraise {
        _ => fail("expected invalid exact path: " + path)
      }
      try
        path_filter(root, options, file_paths=Some(["good.txt", path]))
      catch {
        SelectionError::InvalidPattern(source~, pattern~, ..) => {
          assert_eq(source, "file_paths")
          assert_eq(pattern, path)
        }
        e => raise e
      } noraise {
        _ => fail("expected invalid filter path: " + path)
      }
    }
    // A valid listed path still propagates malformed rules, rather than skipping.
    try select(root, options, file_paths=Some(["good.txt"])) catch {
      SelectionError::InvalidPattern(source~, line~, ..) => {
        assert_eq(source, join(root, ".repomixignore"))
        assert_eq(line, 1)
      }
      e => raise e
    } noraise {
      _ => fail("expected malformed rule failure")
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "exact paths inspect every ancestor without following links or opening candidate bodies" {
  fixture() <| directory => {
    init_git(directory)
    let root = join(directory, "root")
    put(root, "safe/file.txt", "body")
    put(root, "regular", "body")
    put(root, "back\\slash.txt", "Git-only POSIX spelling")
    put(directory, "outside/.repomixignore", "[invalid\n")
    put(directory, "outside/secret.txt", "outside")
    @fs.symlink(target=join(directory, "outside"), join(root, "linked"))
    @fs.symlink(target=join(root, "safe/file.txt"), join(root, "file-link"))
    @fs.symlink(target=join(root, "missing-target"), join(root, "broken"))
    let (code, _, error) = @process.collect_output("mkfifo", [
      join(root, "pipe"),
    ])
    assert_eq(code, 0, msg=error.text())
    @fs.chmod(join(root, "safe/file.txt"), 0)
    let paths = [
      "linked/secret.txt", "linked", "file-link", "broken/child", "regular/child",
      "pipe/child", "pipe", "safe", "safe/file.txt", "absent/child",
    ]
    let options = SelectionOptions::default()
    let result = @async.with_timeout(5000, () => {
      select(root, options, file_paths=Some(paths))
    })
    assert_eq(result.files.map(f => f.relative), ["safe/file.txt"])
    assert_eq(result.skipped.map(s => (s.path, s.reason)), [
      ("absent/child", "MissingFile"),
      ("broken/child", "Symlink"),
      ("file-link", "Symlink"),
      ("linked", "Symlink"),
      ("linked/secret.txt", "Symlink"),
      ("pipe", "UnsupportedFileType"),
      ("pipe/child", "UnsupportedFileType"),
      ("regular/child", "NotDirectory"),
      ("safe", "Directory"),
    ])
    let filter = path_filter(root, options, file_paths=Some(paths))
    for path in paths {
      assert_eq(
        filter.allows(path),
        path == "safe/file.txt" || path == "absent/child",
        msg=path,
      )
    }
    let git_filter = path_filter(root, options)
    assert_true(git_filter.allows("back\\slash.txt"))
    @fs.symlink(target=root, join(directory, "output-alias"))
    let output = select(
      root,
      {
        ..options,
        output: Some(join(directory, "output-alias/safe/file.txt")),
      },
      file_paths=Some(["safe/file.txt"]),
    )
    assert_eq(output.files.length(), 0)
    assert_eq(output.skipped.map(s => (s.path, s.reason)), [
      ("safe/file.txt", "OutputFile"),
    ])
    let output_filter = path_filter(
      root,
      {
        ..options,
        output: Some(join(directory, "output-alias/safe/file.txt")),
      },
      file_paths=Some(["safe/file.txt"]),
    )
    assert_false(output_filter.allows("safe/file.txt"))
  }
}
