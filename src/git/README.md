# Safe Git context (native)

`Delthin/moon_repomix/git` is opt-in: `collect(directory, diffs=true, logs=10)`
returns per-file staged/unstaged patches and structured commits. Defaults collect
neither. `repository_root` is the actual Git root; **all file paths and patch
headers are relative to the selected directory**, including when it is below the
Git root. Renames contain both old and new paths. A rename crossing the selected
scope is reported as an addition/deletion inside it. Untracked files are not Git
diffs. An unborn branch returns `revision=None`, staged patches and no commits.
Commit dates use ISO 8601 author dates, messages preserve bodies/newlines, and
files are deduplicated across merge parents. Path-limited Git log follows Git's
normal history simplification. Callers must apply include/ignore and secret
filtering before rendering any returned content.

All Git calls use argument arrays, a restricted environment, no inherited/global
Git configuration, disabled hooks/fsmonitor/signature display/external diff/
textconv/credential helpers/submodules/replace objects/automatic maintenance.
Worktree diffs also disable every configured clean/process attribute filter,
including filters from included repository configuration. Git metadata is read,
not rewritten. Concurrent malicious modification of repository/config files is
not a supported isolation boundary. Git executable and system CA trust must be
trusted. Non-UTF-8 output raises `GitError::InvalidOutput` rather than silently
misidentifying paths. NUL-delimited paths preserve spaces, tabs and newlines.

Every command has a 30-second deadline; `collect` has an aggregate stdout/stderr
budget (`max_bytes=8388608`). Exceeding limits raises, never truncates. Git errors
contain the operation and exit code, not child diagnostics, URLs or source text.
`NotRepository` is explicit; filesystem, timeout and cancellation errors propagate.
The caller must not reinterpret cancellation/errors as empty successful context.
