///|
// repomix 1.18.1 defaultIgnore.ts. Bare patterns stay root-relative;
// only explicit '**/' patterns apply at every depth.
fn default_patterns(enabled : Bool) -> Array[Pattern] raise SelectionError {
  if !enabled {
    return []
  }
  let patterns = [
    ".git/**", ".hg/**", ".hgignore", ".svn/**", "**/node_modules/**", "**/bower_components/**",
    "**/jspm_packages/**", "vendor/**", "**/.bundle/**", "**/.gradle/**", "target/**",
    "logs/**", "**/*.log", "**/npm-debug.log*", "**/yarn-debug.log*", "**/yarn-error.log*",
    "pids/**", "*.pid", "*.seed", "*.pid.lock", "lib-cov/**", "coverage/**", ".nyc_output/**",
    ".grunt/**", ".lock-wscript", "build/Release/**", "typings/**", "**/.npm/**",
    ".eslintcache", ".rollup.cache/**", ".webpack.cache/**", ".parcel-cache/**",
    ".sass-cache/**", "*.cache", ".node_repl_history", "*.tgz", "**/.yarn/**", "**/.yarn-integrity",
    ".env", ".next/**", ".nuxt/**", ".vuepress/dist/**", ".serverless/**", ".fusebox/**",
    ".dynamodb/**", "dist/**", "**/.DS_Store", "**/Thumbs.db", ".idea/**", ".vscode/**",
    "**/*.swp", "**/*.swo", "**/*.swn", "**/*.bak", "build/**", "out/**", "tmp/**",
    "temp/**", "**/repomix-output.*", "**/repopack-output.*", "**/package-lock.json",
    "**/yarn-error.log", "**/yarn.lock", "**/pnpm-lock.yaml", "**/bun.lockb", "**/bun.lock",
    "**/__pycache__/**", "**/*.py[cod]", "**/venv/**", "**/.venv/**", "**/.pytest_cache/**",
    "**/.mypy_cache/**", "**/.ipynb_checkpoints/**", "**/Pipfile.lock", "**/poetry.lock",
    "**/uv.lock", "**/Cargo.lock", "**/Cargo.toml.orig", "**/target/**", "**/*.rs.bk",
    "**/composer.lock", "**/Gemfile.lock", "**/go.sum", "**/mix.lock", "**/stack.yaml.lock",
    "**/cabal.project.freeze",
    // Project safety defaults also cover nested metadata and native build trees.
     "**/.git", "**/.hg", "**/.svn", "**/node_modules", "**/_build", "**/.DS_Store",
  ]
  let result : Array[Pattern] = []
  for raw in patterns {
    let pattern = compile_pattern(raw, "default", 0, true)
    result.push({ ..pattern, basename: false, })
    if raw.has_suffix("/**") {
      // The upstream pattern excludes every descendant. Prune only an ordinary
      // matching directory, after no-follow classification, never a same-name file.
      let directory = compile_pattern(
        raw[:raw.length() - 2].to_owned(),
        "default",
        0,
        true,
      )
      result.push({ ..directory, basename: false, })
    }
  }
  result
}
