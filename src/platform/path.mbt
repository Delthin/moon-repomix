///|
extern "c" fn windows_ffi() -> Int32 = "mr_windows"

///|
extern "c" fn pid() -> Int32 = "mr_pid"

///|
extern "c" fn executable_ffi() -> Bytes = "mr_executable"

///|
pub fn is_windows() -> Bool {
  windows_ffi() != 0
}

///|
pub fn separators(path : String) -> String {
  if is_windows() {
    path.replace_all(old="\\", new="/")
  } else {
    path
  }
}

///|
pub fn join(parent : String, child : String) -> String {
  if parent.has_suffix("/") {
    parent + child
  } else {
    parent + "/" + child
  }
}

///|
pub fn parent(path : String) -> String {
  let path = separators(path)
  match path.rev_find("/") {
    Some(0) => "/"
    Some(i) if i == 2 && path[1] == ':' => path[:3].to_owned()
    Some(i) => path[:i].to_owned()
    None => "."
  }
}

///|
pub fn basename(path : String) -> String {
  let path = separators(path)
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
pub fn absolute(path : String, cwd : String) -> String {
  let path = separators(path)
  if path.has_prefix("/") ||
    (is_windows() && path.length() >= 3 && path[1] == ':' && path[2] == '/') {
    path
  } else {
    join(cwd, path)
  }
}

///|
/// Resolve the parent, without following a possibly linked output file.
pub async fn output_path(path : String, cwd : String) -> String {
  let path = absolute(path, cwd)
  let name = basename(path)
  if name == "" || name == "." || name == ".." {
    raise OutputError
  }
  let directory = @fs.realpath(parent(path))
  join(separators(directory), name)
}

///|
pub async fn executable_path() -> String {
  let bytes = executable_ffi()
  if bytes.is_empty() {
    raise OutputError
  }
  separators(@fs.realpath(@utf8.decode(bytes)))
}

///|
fn tokenizer_path_for_executable(executable : String, windows : Bool) -> String {
  let comparable = if windows { executable.to_lower() } else { executable }
  for profile in ["debug", "release"] {
    let suffix = "/_build/native/\{profile}/build/cmd/moon-repomix/moon-repomix.exe"
    if comparable.has_suffix(suffix) {
      let root = executable[:executable.length() - suffix.length()].to_owned()
      return join(root, "assets/tokenizer-o200k_base.tiktoken")
    }
  }
  join(parent(parent(executable)), "share/moon-repomix/o200k_base.tiktoken")
}

///|
/// Resolve resources beside the installation or in the standard native source build.
pub async fn tokenizer_path() -> String {
  tokenizer_path_for_executable(executable_path(), is_windows())
}

///|
pub(all) suberror OutputError
