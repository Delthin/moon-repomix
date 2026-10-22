///|
async fn fixture(run : async (String) -> Unit) -> Unit {
  @async.with_task_group() <| group => {
    let directory = @fs.tmpdir(prefix="selection-")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(directory, recursive=true))
    })
    let directory = canonical(directory)
    run(directory)
  }
}

///|
async fn git(
  directory : String,
  args : Array[String],
) -> (Int32, String, String) {
  let (code, out, err) = @process.collect_output("git", args, cwd=directory, extra_env={
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": "/dev/null",
  })
  (code, out.text(), err.text())
}

///|
async fn init_git(directory : String) -> Unit {
  let (code, _, error) = git(directory, [
    "-c", "init.defaultBranch=main", "init", "--quiet",
  ])
  assert_eq(code, 0, msg=error)
}

///|
async fn put(root : String, path : String, content : String) -> Unit {
  let target = join(root, path)
  if optional_kind(parent(target)) is None {
    @fs.mkdir(parent(target), recursive=true)
  }
  @fs.write_file(target, content, create_mode=CreateOrTruncate)
}

///|
fn selected(selection : Selection, path : String) -> Bool {
  selection.files.any(file => file.relative == path)
}

///|
test "glob validation, recursive components, classes, directory includes and UTF8 order" {
  for
    bad in [
      "", "/absolute", "C:/absolute", "\\absolute", "\\\\server\\share", "../escape",
      "a/../b", "a//b", "!negate", "a**b", "[", "[z-a]", "foo\\",
    ] {
    let rejected = try {
      ignore(compile_pattern(bad, "include", 0, true))
      false
    } catch {
      SelectionError::InvalidPattern(..) => true
      e => raise e
    }
    assert_true(rejected, msg=bad)
  }
  let compile = (pattern : String) => compile_pattern(pattern, "test", 1, false)
  assert_true(compile("a/**/b?.[ch]").matches("a/b1.c", false))
  assert_true(compile("a/**/b?.[ch]").matches("a/x/y/b2.h", false))
  assert_false(compile("a/*/b?.[ch]").matches("a/x/y/b2.h", false))
  assert_false(compile("tail/**").matches("tail", true))
  assert_true(compile("tail/**").matches("tail/child", true))
  assert_true(compile("**/tail/**").matches("tail/child", false))
  assert_true(compile("**/tail/**").matches("x/tail/tail", true))
  assert_true(compile("[!a-c]?.txt").matches("z1.txt", false))
  assert_true(compile("[]a].txt").matches("].txt", false))
  assert_true(compile("\\#literal.txt").matches("#literal.txt", false))
  assert_false(compile("?.txt").matches("猫.txt", false))
  assert_true(compile("???.txt").matches("猫.txt", false))
  assert_true(
    compile_pattern("?.txt", "include", 0, true).matches("猫.txt", false),
  )
  assert_true(compile("dir/").matches("a/dir", true))
  assert_false(compile("dir/").matches("dir", false))
  assert_false(compile("/only").matches("a/only", false))
  assert_true(included([compile("src/")], "src/deep/readme.md"))
  assert_false(included([compile("src/*.mbt")], "src/deep/file.mbt"))
  assert_true(utf8_compare("\u{e000}", "\u{10000}") < 0)
  assert_true(utf8_compare("z", "aa") > 0)
  assert_true(utf8_compare("readme.md", "\u{e000}.txt") < 0)
  assert_eq(trim_rule_line("name\\ "), "name\\ ")
  assert_eq(trim_rule_line("name   \r"), "name")
  assert_eq(parent("C:/"), "C:/")
  assert_eq(parent("C:/file"), "C:/")
  assert_eq(parent("//server/share"), "//server/share")
  assert_eq(parent("//server/share/dir"), "//server/share")
  assert_eq(normalize("C:/../../file"), "C:/file")
  assert_eq(normalize("//server/share/../../file"), "//server/share/file")
  assert_eq(within("/root-other/file", "/root"), None)
}

///|
async test "scoped gitignore agrees with Git; excluded parents cannot be re-included" {
  fixture() <| root => {
    init_git(root)
    put(root, ".git/info/exclude", "project/info.txt\n")
    put(root, ".gitignore", "parent-*.txt\n/project/locked/\n")
    put(
      root, "project/.gitignore", "# comment\n/root-only.txt\n*.log\nblocked/\n!blocked/revive.txt\nneg-*.txt\n!neg-keep.txt\n!parent-keep.txt\n\\#literal.txt\n\\!literal.txt\nspace\\ .txt\ntrim.txt   \n/anchored/\ntree/**/x?.[ch]\ntail/**\n[ab].txt\n?.uni\n???.multi\n字.txt\nreopen/\n!reopen/\nreopen/*\n!reopen/keep.txt\n",
    )
    put(
      root, "project/nested/.gitignore", "!parent-drop.txt\n!neg-child.txt\n/keep-local.txt\n",
    )
    put(root, "project/blocked/.gitignore", "[invalid\n")
    put(root, "project/locked/.gitignore", "[invalid\n")
    let cases : Array[(String, Bool)] = [
      ("info.txt", true),
      ("root-only.txt", true),
      ("nested/root-only.txt", false),
      ("parent-drop.txt", true),
      ("parent-keep.txt", false),
      ("nested/parent-drop.txt", false),
      ("nested/neg-child.txt", false),
      ("nested/keep-local.txt", true),
      ("neg-drop.txt", true),
      ("neg-keep.txt", false),
      ("nested/a.log", true),
      ("blocked/revive.txt", true),
      ("locked/revive.txt", true),
      ("#literal.txt", true),
      ("!literal.txt", true),
      ("space .txt", true),
      ("trim.txt", true),
      ("anchored/file.txt", true),
      ("nested/anchored/file.txt", false),
      ("tree/x1.c", true),
      ("tree/deep/x2.h", true),
      ("tree/deep/x22.h", false),
      ("tail/file.txt", true),
      ("a.txt", true),
      ("b.txt", true),
      ("c.txt", false),
      ("猫.uni", false),
      ("a.uni", true),
      ("猫.multi", true),
      ("字.txt", true),
      ("reopen/keep.txt", false),
      ("reopen/drop.txt", true),
    ]
    for item in cases {
      put(root, "project/" + item.0, "not read")
    }
    let options = {
      ..SelectionOptions::default(),
      include_patterns: [
        "**/*.txt", "**/*.log", "**/*.c", "**/*.h", "**/*.uni", "**/*.multi",
      ],
      use_dot_ignore: false,
    }
    let result = select(join(root, "project"), options)
    for item in cases {
      let (code, _, error) = git(root, [
        "-c",
        "core.excludesFile=/dev/null",
        "check-ignore",
        "--no-index",
        "--quiet",
        "--",
        "project/" + item.0,
      ])
      assert_true(code == 0 || code == 1, msg=error)
      assert_eq(code == 0, item.1, msg="Git fixture expectation: " + item.0)
      assert_eq(selected(result, item.0), !item.1, msg=item.0)
    }
    for directory in ["blocked", "locked", "anchored"] {
      assert_eq(result.skipped.filter(s => s.path == directory).length(), 1)
      assert_false(result.skipped.any(s => s.path.has_prefix(directory + "/")))
    }
    assert_true(result.skipped.any(s => s.path == "tail/file.txt"))
    let blocked_root = select(join(root, "project/locked"), options)
    assert_eq(blocked_root.files.length(), 0)
    assert_eq(blocked_root.skipped.map(s => s.path), ["."])
  }
}

///|
async test "dot layers, deeper overrides, custom final exclusions and independent switches" {
  fixture() <| root => {
    init_git(root)
    put(root, ".gitignore", "same.txt\nonly-git.txt\n")
    put(root, ".ignore", "!same.txt\n*.dot\n")
    put(root, ".repomixignore", "same.txt\n!take.dot\n")
    put(root, "nested/.gitignore", "!same.txt\n")
    for
      path in [
        "same.txt", "only-git.txt", "take.dot", "drop.dot", "nested/same.txt", "node_modules/pkg.txt",
        ".git/sentinel.txt",
      ] {
      put(root, path, "data")
    }
    let normal = select(root, SelectionOptions::default())
    assert_false(selected(normal, "same.txt"))
    assert_true(selected(normal, "nested/same.txt"))
    assert_true(selected(normal, "take.dot"))
    assert_false(selected(normal, "drop.dot"))
    assert_false(selected(normal, "only-git.txt"))
    assert_false(selected(normal, "node_modules/pkg.txt"))
    let custom = select(root, {
      ..SelectionOptions::default(),
      ignore: ["same.txt", "take.dot"],
    })
    assert_false(selected(custom, "nested/same.txt"))
    assert_false(selected(custom, "take.dot"))
    let no_git = select(root, {
      ..SelectionOptions::default(),
      use_gitignore: false,
    })
    assert_true(selected(no_git, "only-git.txt"))
    assert_false(selected(no_git, "drop.dot"))
    let no_dot = select(root, {
      ..SelectionOptions::default(),
      use_dot_ignore: false,
    })
    assert_true(selected(no_dot, "drop.dot"))
    assert_false(selected(no_dot, "same.txt"))
    let no_git_or_dot = select(root, {
      ..SelectionOptions::default(),
      use_gitignore: false,
      use_dot_ignore: false,
    })
    assert_false(selected(no_git_or_dot, "same.txt"))
    assert_true(selected(no_git_or_dot, "drop.dot"))
    let no_defaults = select(root, {
      ..SelectionOptions::default(),
      use_default_patterns: false,
    })
    assert_true(selected(no_defaults, "node_modules/pkg.txt"))
    assert_true(selected(no_defaults, ".git/sentinel.txt"))
  }
}

///|
#cfg(not(platform="windows"))
async test "output aliases, nonordinary files, include directories and UTF8 ordering" {
  fixture() <| parent_dir => {
    init_git(parent_dir)
    let root = join(parent_dir, "root")
    put(root, "src/readme.md", "not opened")
    put(root, "src/output.txt", "old output")
    put(root, "other.txt", "not included")
    put(root, "src/\u{e000}.txt", "BMP")
    put(root, "src/\u{10000}.txt", "supplementary")
    put(root, "colon:", "output ending in colon")
    @fs.symlink(target=root, join(parent_dir, "alias"))
    @fs.symlink(target=join(root, "src"), join(root, "linked"))
    @fs.symlink(target=join(root, "missing"), join(root, "broken"))
    @fs.symlink(
      target=join(root, "src/output.txt"),
      join(parent_dir, "output-alias"),
    )
    @fs.symlink(target=join(root, "src"), join(parent_dir, "cwd-alias"))
    let (code, _, error) = @process.collect_output("mkfifo", [
      join(root, "pipe"),
    ])
    assert_eq(code, 0, msg=error.text())
    @fs.chmod(join(root, "src/readme.md"), 0)
    let options = {
      ..SelectionOptions::default(),
      include_patterns: ["src/"],
      output: Some(join(parent_dir, "alias/src/output.txt")),
    }
    let result = @async.with_timeout(5000, () => select(root, options))
    assert_eq(result.files.map(f => f.relative), [
      "src/readme.md", "src/\u{e000}.txt", "src/\u{10000}.txt",
    ])
    for file in result.files {
      assert_eq(file.path, join(result.root, file.relative))
    }
    assert_true(
      result.skipped.any(s => {
        s.path == "src/output.txt" && s.reason == "OutputFile"
      }),
    )
    assert_true(
      result.skipped.any(s => {
        s.path == "pipe" && s.reason == "UnsupportedFileType"
      }),
    )
    assert_true(
      result.skipped.any(s => s.path == "broken" && s.reason == "Symlink"),
    )
    assert_true(
      result.skipped.any(s => s.path == "linked" && s.reason == "Symlink"),
    )
    let file_alias = select(root, {
      ..options,
      output: Some(join(parent_dir, "output-alias")),
    })
    assert_false(selected(file_alias, "src/output.txt"))
    let colon_output = select(root, {
      ..SelectionOptions::default(),
      output: Some(join(root, "colon:")),
    })
    assert_false(selected(colon_output, "colon:"))
    let dotdot_alias = select(root, {
      ..options,
      output: Some(join(parent_dir, "cwd-alias/../src/output.txt")),
    })
    assert_false(selected(dotdot_alias, "src/output.txt"))
    let missing_output = select(root, {
      ..options,
      output: Some(join(parent_dir, "alias/new/deep/output.txt")),
    })
    assert_true(selected(missing_output, "src/output.txt"))
    for suffix in ["", "/", "//", "/.", "//./"] {
      let symlink_root = try {
        ignore(select(join(parent_dir, "alias") + suffix, options))
        false
      } catch {
        SelectionError::InvalidRoot(_) => true
        e => raise e
      }
      assert_true(symlink_root, msg=suffix)
    }
  }
}

///|
async test "no Git ancestor inherits to filesystem root, and worktree commondir exclude" {
  fixture() <| directory => {
    put(directory, ".gitignore", "inherited.txt\n")
    put(directory, "root/inherited.txt", "data")
    put(directory, "root/keep.txt", "data")
    let result = select(join(directory, "root"), SelectionOptions::default())
    assert_false(selected(result, "inherited.txt"))
    assert_true(selected(result, "keep.txt"))
    // Synthetic equivalent of a linked worktree, without touching a real repo.
    put(directory, "main/.git/info/exclude", "from-info.txt\n")
    put(directory, "main/.git/worktrees/linked/commondir", "../..\n")
    put(directory, "linked/.git", "gitdir: ../main/.git/worktrees/linked\n")
    put(directory, "linked/from-info.txt", "data")
    put(directory, "linked/keep.txt", "data")
    let worktree = select(
      join(directory, "linked"),
      SelectionOptions::default(),
    )
    assert_false(selected(worktree, "from-info.txt"))
    assert_true(selected(worktree, "keep.txt"))
  }
}

///|
#cfg(not(platform="windows"))
async test "rule errors and symlink metadata are fatal, never followed" {
  fixture() <| root => {
    init_git(root)
    put(root, "good.txt", "data")
    for invalid in ["relative", join(root, "good.txt"), join(root, "missing")] {
      let rejected = try {
        ignore(select(invalid, SelectionOptions::default()))
        false
      } catch {
        SelectionError::InvalidRoot(_) => true
        e => raise e
      }
      assert_true(rejected, msg=invalid)
    }
    let invalid_output = try {
      ignore(
        select(root, {
          ..SelectionOptions::default(),
          output: Some("relative.txt"),
        }),
      )
      false
    } catch {
      SelectionError::InvalidOutput(_) => true
      e => raise e
    }
    assert_true(invalid_output)
    @fs.write_file(join(root, ".gitignore"), b"\xff", create_mode=CreateNew)
    let invalid_utf8 = try {
      ignore(select(root, SelectionOptions::default()))
      false
    } catch {
      @utf8.Malformed(_) => true
      e => raise e
    }
    assert_true(invalid_utf8)
    @fs.remove(join(root, ".gitignore"))
    @fs.symlink(target=join(root, "good.txt"), join(root, ".gitignore"))
    let linked_rule = try {
      ignore(select(root, SelectionOptions::default()))
      false
    } catch {
      SelectionError::InvalidRuleFile(_) => true
      e => raise e
    }
    assert_true(linked_rule)
    @fs.remove(join(root, ".gitignore"))
    let (code, _, error) = @process.collect_output("mkfifo", [
      join(root, ".gitignore"),
    ])
    assert_eq(code, 0, msg=error.text())
    let pipe_rule = try {
      ignore(
        @async.with_timeout(5000, () => {
          select(root, SelectionOptions::default())
        }),
      )
      false
    } catch {
      SelectionError::InvalidRuleFile(_) => true
      e => raise e
    }
    assert_true(pipe_rule)
    @fs.remove(join(root, ".gitignore"))
    put(root, ".gitignore", "[invalid\n")
    let invalid_rule = try {
      ignore(select(root, SelectionOptions::default()))
      false
    } catch {
      SelectionError::InvalidPattern(source~, line~, ..) => {
        assert_eq(source, join(root, ".gitignore"))
        assert_eq(line, 1)
        true
      }
      e => raise e
    }
    assert_true(invalid_rule)
    let disabled = select(root, {
      ..SelectionOptions::default(),
      use_gitignore: false,
    })
    assert_true(selected(disabled, "good.txt"))
    @fs.remove(join(root, ".gitignore"))
    @fs.rename(join(root, ".git/info"), join(root, "info-real"))
    @fs.symlink(target=join(root, "info-real"), join(root, ".git/info"))
    let linked_info = try {
      ignore(select(root, SelectionOptions::default()))
      false
    } catch {
      SelectionError::InvalidGitMetadata(_) => true
      e => raise e
    }
    assert_true(linked_info)
  }
}
