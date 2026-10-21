///|
#borrow(path)
extern "c" fn remove_owned_tree_ffi(path : Bytes) -> Int32 = "mr_remove_owned_tree"

///|
/// Remove a caller-owned temporary tree, including read-only Git objects.
/// Ownership must be established by the caller, not inferred from a path prefix.
/// Rejects a linked root; removes child symlinks/junctions without following them.
/// Does not change permissions through paths. Errors (including partial removal)
/// propagate so the caller can retain its ownership record for recovery.
/// This synchronous native operation cannot be interrupted by task cancellation.
pub fn remove_owned_tree(path : String) -> Unit raise {
  if path.is_empty() || path.contains("\u0000") {
    raise OutputError
  }
  let code = remove_owned_tree_ffi(@utf8.encode(path + "\u0000"))
  if code != 0 {
    raise @os_error.OSError(code, context="remove owned temporary tree")
  }
}
