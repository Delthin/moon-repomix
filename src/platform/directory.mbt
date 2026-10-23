///|
/// A UTF-8 text file in a flat directory publication.
pub(all) struct DirectoryEntry {
  name : String
  text : String
}

///|
// Portable single components: in particular, never allow Windows device names
// or alternate data streams to turn a file creation into a different operation.
fn directory_component(name : String) -> Bool {
  if name.is_empty() ||
    name == "." ||
    name == ".." ||
    name.has_suffix(".") ||
    name.has_suffix(" ") {
    return false
  }
  for char in name {
    if char <= '\u001f' ||
      char is ('/' | '\\' | ':' | '<' | '>' | '"' | '|' | '?' | '*') {
      return false
    }
  }
  let stem = match name.find(".") {
    Some(index) => name[:index].to_owned().to_lower()
    None => name.to_lower()
  }
  match stem {
    "con" | "prn" | "aux" | "nul" | "conin$" | "conout$" => false
    _ => {
      if stem.has_prefix("com") || stem.has_prefix("lpt") {
        if stem.length() == 4 && stem[3] is ('1'..<='9' | '¹' | '²' | '³') {
          return false
        }
      }
      true
    }
  }
}

///|
async fn directory_target_absent(path : String) -> Unit {
  let _ = @fs.kind(path, follow_symlink=false) catch {
    @os_error.OSError(_, context=_) as err if err.is_ENOENT() => return
    err => raise err
  }
  raise OutputError
}

///|
/// Resolve an existing parent, retaining the final component without following
/// it. Ordinary trailing separators are accepted; existing targets (including
/// dangling links), roots and invalid components raise an error.
pub async fn directory_output_path(path : String, cwd : String) -> String {
  if path.is_empty() || path.contains("\u0000") || cwd.contains("\u0000") {
    raise OutputError
  }
  let path = separators(path)
  let mut end = path.length()
  while end > 0 && path[end - 1] == '/' {
    end -= 1
  }
  let path = path[:end].to_owned()
  if path.is_empty() || !directory_component(basename(path)) {
    raise OutputError
  }
  let path = absolute(path, cwd)
  let directory = @fs.realpath(parent(path))
  if @fs.kind(directory) != @fs.Directory {
    raise OutputError
  }
  let target = join(separators(directory), basename(path))
  directory_target_absent(target)
  target
}

///|
#borrow(source, target)
extern "c" fn directory_noreplace_ffi(source : Bytes, target : Bytes) -> Int32 = "mr_directory_noreplace"

///|
// Synchronous: success and ownership transfer cannot be split by cancellation.
fn directory_noreplace(source : String, target : String) -> Unit raise {
  let code = directory_noreplace_ffi(
    @utf8.encode(source + "\u0000"),
    @utf8.encode(target + "\u0000"),
  )
  if code != 0 {
    raise @os_error.OSError(
      code,
      context="publish directory without replacement",
    )
  }
}

///|
let directory_sequence : Ref[Int64] = Ref(0)

///|
/// Write and sync each file in a fresh private sibling directory, then publish
/// with an atomic no-replace move. Only this invocation's staging is removed on
/// failure/cancellation; a published target is never removed. Cancellation can
/// be observed after publication, in which case the complete target remains.
/// The parent must exist. Names must be unique portable single components.
pub async fn commit_directory(
  target : String,
  entries : Array[DirectoryEntry],
) -> Unit {
  // Snapshot the mutable array before the first suspension.
  let entries = entries.copy()
  let names : Map[String, Unit] = Map([])
  for entry in entries {
    if !directory_component(entry.name) || names.contains(entry.name) {
      raise OutputError
    }
    names[entry.name] = ()
  }
  let target = directory_output_path(target, ".")
  directory_sequence.val += 1
  let staging = join(
    parent(target),
    ".moon-repomix-dir-\{pid()}-\{@env.now()}-\{directory_sequence.val}.tmp",
  )
  let mut owned = false
  errdefer (if owned { remove_owned_tree(staging) })
  // Record ownership before a pending cancellation can escape mkdir. A name
  // collision fails without adopting or cleaning the pre-existing directory.
  @async.protect_from_cancel(() => {
    @fs.mkdir(staging, permission=0o700)
    owned = true
  })
  for entry in entries {
    // File is an unbuffered Writer (no separate flush API). Shield acquisition
    // through close so cancellation cannot strand an open file during cleanup.
    @async.protect_from_cancel(() => {
      let file = @fs.create(
        join(staging, entry.name),
        allow_existing=false,
        permission=0o600,
      )
      defer file.close()
      @io.Writer::write(file, entry.text)
      file.sync()
    })
  }
  directory_target_absent(target)
  directory_noreplace(staging, target)
  owned = false
}
