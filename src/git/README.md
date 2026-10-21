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
filtering before rendering any returned content. Optional
`accept_diff : async (Array[String]) -> Bool` receives each rename-aware path
group before its patch is read; return false to avoid collecting ignored large
patches. Returned history still requires the caller's path filtering.

All Git calls use argument arrays, a restricted environment, no inherited/global
Git configuration, disabled hooks/fsmonitor/signature display/external diff/
textconv/credential helpers/submodules/replace objects/automatic maintenance.
Only PATH and OS runtime variables (SystemRoot, WINDIR, TEMP, TMP, TMPDIR,
PATHEXT) are copied from the host; injected GIT_* and shell/helper variables are
not inherited. Configuration null devices use `NUL` on Windows and `/dev/null`
elsewhere. Child stdin is an EOF pipe, never an inherited terminal or an async
file open on a Windows device.
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

## HTTPS checkout

`checkout(url, revision~, history=10)` accepts an optional revision (omit the label
for default branch HEAD), returning `{ directory, url, revision }` with the actual
resolved HEAD. Branch/tag names and full commit IDs are supported; revisions are
restricted to ASCII letters/digits, `.`, `_`, `-`, `/` and valid ref components,
not refspecs, options or revision expressions. Public HTTPS URLs must use a DNS
hostname (not IP literals or local-only hostnames), an optional valid port, no
userinfo/credentials, query, fragment, whitespace/control characters or backslash.
Valid percent escapes in paths are accepted except encoded controls/backslashes.
DNS resolution, Git installation and system CA trust remain host responsibilities;
this is not a DNS-rebinding/SSRF firewall. TLS verification is required, redirects
are disabled, and credentials/private repositories/submodules are unsupported.

A fresh empty-template Git repository is initialized in a private temporary
directory, then fetch/checkout run through the same hardened runner. No Git hooks
or filters are installed from the host. Default `history=0` fetches depth 1;
`history>0` fetches full ancestry of the selected ref, not merely that many commits,
so path-limited history has sufficient ancestry. `.git` remains available for
`collect`. The complete checkout operation shares an 8 MiB captured-output budget;
each command has the same 30-second deadline. This is not a disk/network quota.

Always `defer cleanup(checkout)` after success. Failure/cancellation before return
removes the temporary directory. Both paths protect deletion in already-cancelled
tasks and subsequently resume cancellation. Cleanup only accepts directories
allocated by this package in the same process; public struct fields do not grant
permission to delete arbitrary paths. Successful cleanup invalidates the handle
(do not call concurrently or twice). Deletion errors propagate and retain ownership
so the caller can retry explicitly. Native cleanup removes read-only Git objects;
child symlinks/junctions are removed, never followed, and a linked root is rejected.
Windows clears read-only attributes through the exact no-follow file handle,
not path-based chmod; read-only files with multiple hardlinks are rejected to
avoid changing attributes of a potentially foreign file.

Package tests use one synthetic real repository for scoped diff/log and dangerous
extension markers (POSIX marker execution, Windows uses failing extension config),
plus URL validation and local lifecycle failure/cancellation/foreign-path/symlink
checks. They make no network requests. The CLI's `scripts/advanced-context-test.mbtx`
provides local integration coverage and an explicit `--remote-smoke` public HTTPS
case; ordinary CI uses the local cases.
