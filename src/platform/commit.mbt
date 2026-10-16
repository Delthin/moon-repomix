///|
async fn reject_link(path : String) -> Unit {
  let kind = @fs.kind(path, follow_symlink=false) catch {
    @os_error.OSError(_, context=_) as err if err.is_ENOENT() => return
    err => raise err
  }
  if kind != @fs.Regular {
    raise OutputError
  }
}

///|
/// Write a sibling temporary file before replacing the destination.
/// Existing links and non-regular targets are rejected.
pub async fn commit(path : String, content : String) -> Unit {
  reject_link(path)
  let temporary = path + ".moon-repomix-\{pid()}-\{@env.now()}.tmp"
  let file = @fs.create(temporary, allow_existing=false, permission=0o600)
  let mut closed = false
  errdefer {
    if !closed {
      file.close()
    }
    @async.protect_from_cancel(
      () => @fs.remove(temporary) catch { _ => () },
      resume_on_cancel=false,
    )
  }
  @io.Writer::write(file, content)
  file.sync()
  file.close()
  closed = true
  reject_link(path)
  @fs.rename(temporary, path, replace=true)
}

///|
/// Create configuration only if the path does not already exist.
pub async fn create_new(path : String, content : String) -> Unit {
  let file = @fs.create(path, allow_existing=false)
  defer file.close()
  @io.Writer::write(file, content)
}
