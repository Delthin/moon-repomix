///|
fn diff_arguments(staged : Bool) -> Array[String] {
  let args = [
    "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--relative", "--find-renames",
    "--ignore-submodules=all",
  ]
  if staged {
    args.push("--cached")
  }
  args
}

///|
async fn collect_diffs(
  directory : String,
  budget : Budget,
  accept_diff : (async (Array[String]) -> Bool)?,
) -> Array[Diff] {
  let result = []
  for staged in [true, false] {
    let args = diff_arguments(staged)
    args.append(["--name-status", "-z", "--", "."])
    let groups = changed_paths(git(directory, args, budget))
    for paths in groups {
      if accept_diff is Some(accept) && !accept(paths) {
        continue
      }
      let patch_args = diff_arguments(staged)
      patch_args.append(["--patch", "--src-prefix=a/", "--dst-prefix=b/", "--"])
      patch_args.append(paths)
      let text = git(directory, patch_args, budget)
      if !text.is_empty() {
        result.push({
          kind: if staged {
            "staged"
          } else {
            "unstaged"
          },
          paths,
          text,
        })
      }
    }
  }
  result
}

///|
async fn collect_commits(
  directory : String,
  count : Int32,
  budget : Budget,
) -> Array[Commit] {
  let ids = nul_fields(
    git(
      directory,
      [
        "log",
        "--no-show-signature",
        "--no-ext-diff",
        "--no-textconv",
        "--format=%H",
        "-z",
        "-n",
        count.to_string(),
        "--",
        ".",
      ],
      budget,
    ),
  )
  let result = []
  for id in ids {
    let info = nul_fields(
      git(
        directory,
        [
          "show", "--no-patch", "--no-show-signature", "--no-ext-diff", "--no-textconv",
          "--format=format:%H%x00%aI%x00%B%x00", id, "--",
        ],
        budget,
      ),
    )
    guard info.length() == 3 && info[0] == id else { raise InvalidOutput }
    let groups = changed_paths(
      git(
        directory,
        [
          "diff-tree", "--root", "--no-commit-id", "--name-status", "-r", "-z", "-m",
          "--no-ext-diff", "--no-textconv", "--relative", "--find-renames", "--ignore-submodules=all",
          id, "--", ".",
        ],
        budget,
      ),
    )
    let files = []
    for paths in groups {
      for path in paths {
        if !files.contains(path) {
          files.push(path)
        }
      }
    }
    result.push({ id, date: info[1], message: info[2], files, })
  }
  result
}

///|
/// Collect tracked changes and history, scoped to directory. Paths (including
/// patch headers) are relative to directory, not necessarily repository_root.
/// max_bytes limits cumulative captured Git output; exceeding it raises rather
/// than returning truncated patches. An unborn HEAD has revision=None and no log.
/// accept_diff filters each rename-aware path group before reading its patch.
/// Call only when Git context is explicitly enabled by the caller.
pub async fn collect(
  directory : String,
  diffs~ : Bool = false,
  logs~ : Int32 = 0,
  max_bytes~ : Int32 = 8388608,
  accept_diff? : async (Array[String]) -> Bool,
) -> Snapshot {
  if logs < 0 || max_bytes <= 0 {
    raise InvalidInput("logs must be nonnegative and max_bytes positive")
  }
  let budget = { remaining: max_bytes, filters: [], }
  let directory = @fs.realpath(directory)
  let (code, inside) = git_raw(
    directory,
    ["rev-parse", "--is-inside-work-tree"],
    budget,
  )
  guard code == 0 && inside == "true\n" else { raise NotRepository }
  let repository_root = line(
    git(directory, ["rev-parse", "--show-toplevel"], budget),
  )
  let (head_code, head) = git_raw(
    directory,
    ["rev-parse", "--verify", "--quiet", "HEAD"],
    budget,
  )
  let revision = if head_code == 0 {
    Some(line(head))
  } else if head_code == 1 {
    // A symbolic HEAD with a missing target is an unborn branch. Other Git
    // failures remain errors; do not turn them into an empty successful log.
    let branch = line(
      git(directory, ["symbolic-ref", "--quiet", "HEAD"], budget),
    )
    let (ref_code, _) = git_raw(
      directory,
      ["show-ref", "--verify", "--quiet", branch],
      budget,
    )
    if ref_code != 1 {
      raise CommandFailed("show-ref", ref_code)
    }
    None
  } else {
    raise CommandFailed("rev-parse", head_code)
  }
  // Worktree diff also invokes clean/process attribute filters. Disable every
  // configured filter (including included configs), not just external diff and
  // textconv. Config inspection itself never runs the configured executables.
  if diffs {
    let (config_code, keys) = git_raw(
      directory,
      [
        "config", "--includes", "--null", "--name-only", "--get-regexp", "^filter\\..*\\.(clean|smudge|process|required)$",
      ],
      budget,
    )
    if config_code != 0 && config_code != 1 {
      raise CommandFailed("config", config_code)
    }
    for key in nul_fields(keys) {
      budget.filters.append(["-c", key + "="])
    }
  }
  let changes = if diffs {
    collect_diffs(directory, budget, accept_diff)
  } else {
    []
  }
  let commits = if logs > 0 && revision is Some(_) {
    collect_commits(directory, logs, budget)
  } else {
    []
  }
  { repository_root, revision, diffs: changes, commits, }
}
