# Directory publication (native)

Public API:

- `pub(all) struct DirectoryEntry { name : String; text : String }`
- `pub async fn directory_output_path(path : String, cwd : String) -> String`
- `pub async fn commit_directory(target : String, entries : Array[DirectoryEntry]) -> Unit`

`directory_output_path` canonicalizes the **existing parent**, not the final
component. Ordinary trailing separators are accepted. Empty, root, dot/parent
components and existing targets (files, directories, links, dangling links) are
rejected. It does not create the parent. `commit_directory` repeats validation,
so a previous path check is not a reservation. Relative targets are resolved
against the process working directory.

Entries are snapshotted before suspension, with exact unique portable flat
names. Empty names, dot/parent, `/`, `\`, `:`, NUL/control characters, Windows
special characters/device names and trailing spaces/dots are rejected. A
filesystem-specific alias collision (for example, case folding) fails exclusive
file creation; it never truncates or merges a previous entry. Contents are
written as UTF-8 without newline or other transformations, including empty text
and embedded NULs. An empty entries array publishes an empty directory.

The implementation exclusively creates a private sibling staging directory
(0700 on Unix) and files (0600 on Unix). The async `File` writer is unbuffered:
write, `File.sync`, and close are performed for every entry, with no separate
flush API. Ownership recording after mkdir and file acquisition-through-close
are cancellation-shielded; pending cancellation is then re-raised. On error or
cancellation, synchronous no-follow `remove_owned_tree` removes only that newly
acquired staging directory. A staging-name collision is an error, not permission
to adopt or clean another directory. Cleanup errors propagate rather than being
silenced. As with other platform outputs, the canonical parent must remain
under the caller's control during the operation.

After rechecking the target without following it, a synchronous native primitive
atomically publishes without replacement:

- macOS: `renamex_np(..., RENAME_EXCL)`
- Linux: `renameat2(..., RENAME_NOREPLACE)` via syscall
- Windows: `MoveFileW` (no replacement/cross-volume-copy flags)

The C arguments are borrowed only for the call. Unsupported kernel/filesystem
semantics fail closed; there is no check-then-ordinary-rename fallback. An
existing destination, including one created after the recheck, is untouched.
Once published, the target is never cleaned up, even if the caller observes
cancellation at a subsequent boundary. This promises atomic visibility, not a
crash-durable parent-directory transaction.

## Focused verification

With the repository toolchain on `PATH` and `MOON_HOME` set:

```sh
moon test src/platform --target native --filter 'directory publication:*'
moon check src/platform --target native
moon info src/platform --target native
```

Three aggregate cases cover exact text/empty output/path normalization; existing
and linked targets/unsafe and duplicate names; staging write failure,
cancellation after an actual staging file appears, foreign-tree preservation,
and direct native no-replace checks against destinations created **after**
preflight (including an empty directory, which plain rename could overwrite).
The latter also tests successful ownership transfer. Unix symlink fixtures are
skipped on Windows, where link creation may require privileges.

Local execution is on macOS. Linux and Windows native branches require their
own CI runs; a successful macOS run does not validate those implementations.
