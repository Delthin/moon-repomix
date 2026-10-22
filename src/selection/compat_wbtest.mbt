///|
async test "upstream defaults preserve root scope, nested safety and directory pruning" {
  fixture() <| root => {
    init_git(root)
    // Concrete filenames independently cover every upstream default category.
    let root_only = [
      ".hgignore", "vendor/pkg/a", "logs/a", "pids/a", "server.pid", "server.seed",
      "server.pid.lock", "lib-cov/a", "coverage/a", ".nyc_output/a", ".grunt/a",
      ".lock-wscript", "build/Release/a", "typings/a", ".eslintcache", ".rollup.cache/a",
      ".webpack.cache/a", ".parcel-cache/a", ".sass-cache/a", "data.cache", ".node_repl_history",
      "archive.tgz", ".env", ".next/a", ".nuxt/a", ".vuepress/dist/a", ".serverless/a",
      ".fusebox/a", ".dynamodb/a", "dist/a", ".idea/a", ".vscode/a", "build/a", "out/a",
      "tmp/a", "temp/a",
    ]
    let recursive = [
      "node_modules/pkg/a", "bower_components/pkg/a", "jspm_packages/pkg/a", ".bundle/a",
      ".gradle/a", "target/a", "run.log", "npm-debug.log.1", "yarn-debug.log.1",
      "yarn-error.log.1", ".npm/a", ".yarn/a", ".yarn-integrity", ".DS_Store", "Thumbs.db",
      "a.swp", "a.swo", "a.swn", "a.bak", "repomix-output.xml", "repopack-output.txt",
      "package-lock.json", "yarn-error.log", "yarn.lock", "pnpm-lock.yaml", "bun.lockb",
      "bun.lock", "__pycache__/a", "a.pyc", "a.pyo", "a.pyd", "venv/a", ".venv/a",
      ".pytest_cache/a", ".mypy_cache/a", ".ipynb_checkpoints/a", "Pipfile.lock",
      "poetry.lock", "uv.lock", "Cargo.lock", "Cargo.toml.orig", "a.rs.bk", "composer.lock",
      "Gemfile.lock", "go.sum", "mix.lock", "stack.yaml.lock", "cabal.project.freeze",
      ".hg/a", ".svn/a", "_build/a",
    ]
    for paths in [root_only, recursive] {
      for path in paths {
        put(root, path, "root")
        put(root, "nested/" + path, "nested")
      }
    }
    put(root, "nested/.git", "metadata safety default")
    put(root, "node_modules/.repomixignore", "[invalid\n")
    let options = { ..SelectionOptions::default(), use_gitignore: false, }
    let result = select(root, options)
    let filter = path_filter(result.root, options)
    for path in root_only {
      assert_false(selected(result, path), msg=path)
      assert_false(filter.allows(path), msg=path)
      assert_true(selected(result, "nested/" + path), msg=path)
      assert_true(filter.allows("nested/" + path), msg=path)
    }
    for path in recursive {
      for relative in [path, "nested/" + path] {
        assert_false(selected(result, relative), msg=relative)
        assert_false(filter.allows(relative), msg=relative)
      }
    }
    assert_false(selected(result, "nested/.git"))
    assert_true(
      result.skipped.any(s => {
        s.path == "vendor" && s.reason == "IgnoredDirectory:default"
      }),
    )
    assert_false(result.skipped.any(s => s.path.has_prefix("vendor/")))
    // A subtree-only default does not exclude an ordinary same-name file.
    put(root, "file-case/vendor", "ordinary file")
    let files = select(join(root, "file-case"), options)
    assert_true(selected(files, "vendor"))
  }
}

///|
async test "include is root-relative while custom and Git basename ignores stay recursive" {
  fixture() <| root => {
    init_git(root)
    for
      path in [
        "LICENSE", "nested/LICENSE", "src/a", "nested/src/a", "nested/drop.txt",
        "nested/git.txt",
      ] {
      put(root, path, "data")
    }
    put(root, ".gitignore", "git.txt\n")
    let options = {
      ..SelectionOptions::default(),
      include_patterns: ["LICENSE", "src", "**/drop.txt", "**/git.txt"],
      ignore: ["drop.txt"],
    }
    let result = select(root, options)
    assert_eq(result.files.map(f => f.relative), ["LICENSE", "src/a"])
    let filter = path_filter(result.root, options)
    assert_true(filter.allows("LICENSE"))
    assert_true(filter.allows("src/a"))
    assert_false(filter.allows("nested/LICENSE"))
    assert_false(filter.allows("nested/src/a"))
    assert_false(filter.allows("nested/drop.txt"))
    assert_false(filter.allows("nested/git.txt"))
  }
}

///|
async test "custom braces expand nested alternatives with bounded products and literal Git braces" {
  let patterns = custom_patterns(
    ["{src,{lib,test}}/*.{mbt,md}", "file[{},].txt", "literal\\{a,b\\}"],
    "include",
  )
  for
    path in [
      "src/a.mbt", "lib/a.md", "test/a.mbt", "file{.txt", "file,.txt", "literal{a,b}",
    ] {
    assert_true(included(patterns, path), msg=path)
  }
  assert_false(included(patterns, "nested/src/a.mbt"))
  let product = "{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}"
  assert_eq(custom_patterns([product], "include").length(), 256)
  assert_eq(custom_patterns(Array::make(256, "plain"), "include").length(), 256)
  let mut nested = "x"
  for _ in 0..<8 {
    nested = "{a," + nested + "}"
  }
  assert_eq(custom_patterns([nested], "include").length(), 9)
  for
    raw in [
      "{a,b",
      "a}",
      "{a,}",
      "{,a}",
      "{}",
      "{a}",
      "{a,{b,}}",
      product + "{a,b}",
      "{a," + nested + "}",
      "{ok,../escape}",
    ] {
    try custom_patterns([raw], "include") catch {
      SelectionError::InvalidPattern(source~, line~, pattern~, ..) => {
        assert_eq(source, "include")
        assert_eq(line, 0)
        assert_eq(pattern, raw)
      }
      e => raise e
    } noraise {
      _ => fail("expected invalid pattern: " + raw)
    }
  }
  try custom_patterns(Array::make(257, "plain"), "ignore") catch {
    SelectionError::InvalidPattern(..) => ()
    e => raise e
  } noraise {
    _ => fail("expected expanded list limit")
  }
  fixture() <| root => {
    init_git(root)
    put(root, ".gitignore", "literal{a,b}.txt\n")
    for
      path in [
        "src/a.mbt", "lib/a.md", "test/a.mbt", "literal{a,b}.txt", "literala.txt",
      ] {
      put(root, path, "data")
    }
    let options = {
      ..SelectionOptions::default(),
      ignore: ["{src,{lib,test}}/*.{mbt,md}"],
    }
    let result = select(root, options)
    let filter = path_filter(result.root, options)
    for path in ["src/a.mbt", "lib/a.md", "test/a.mbt", "literal{a,b}.txt"] {
      assert_false(selected(result, path), msg=path)
      assert_false(filter.allows(path), msg=path)
    }
    assert_true(selected(result, "literala.txt"))
    assert_true(filter.allows("literala.txt"))
  }
}
