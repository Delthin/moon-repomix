///|
#cfg(platform="windows")
fn separators(path : String) -> String {
  path.replace(old="\\", new="/")
}

///|
#cfg(not(platform="windows"))
fn separators(path : String) -> String {
  path
}

///|
#cfg(not(platform="windows"))
fn absolute(path : String) -> Bool {
  path.has_prefix("/")
}

///|
#cfg(platform="windows")
fn absolute(path : String) -> Bool {
  (path.length() >= 3 && drive_prefix(path[:2].to_owned()) && path[2] == '/') ||
  (
    path.has_prefix("//") &&
    path.split("/").filter(p => p != "").collect().length() >= 2
  )
}

///|
fn drive_prefix(path : String) -> Bool {
  path.length() == 2 &&
  path[1] == ':' &&
  ((path[0] >= 'a' && path[0] <= 'z') || (path[0] >= 'A' && path[0] <= 'Z'))
}

///|
fn drive_root(path : String) -> Bool {
  path.length() == 3 && path[2] == '/' && drive_prefix(path[:2].to_owned())
}

///|
fn join(base : String, name : String) -> String {
  if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}

///|
fn parent(path : String) -> String {
  let parts = path.split("/").map(p => p.to_owned()).collect()
  // Preserve drive and UNC share roots, as well as POSIX '/'.
  if parts.length() <= 2 {
    if drive_prefix(parts[0]) {
      return parts[0] + "/"
    }
    return "/"
  }
  if path.has_prefix("//") && parts.length() <= 4 {
    return path
  }
  let result = parts[:parts.length() - 1].to_owned().join("/")
  if drive_prefix(result) {
    result + "/"
  } else {
    result
  }
}

///|
fn basename(path : String) -> String {
  path.split("/").last().unwrap().to_owned()
}

///|
fn normalize(path : String) -> String {
  let path = separators(path)
  let parts : Array[String] = []
  let root_parts = if path.has_prefix("//") {
    2
  } else if path.length() >= 2 && drive_prefix(path[:2].to_owned()) {
    1
  } else {
    0
  }
  for p in path.split("/") {
    if p == "" || p == "." {
      continue
    }
    if p == ".." {
      if parts.length() > root_parts {
        ignore(parts.pop())
      }
    } else {
      parts.push(p.to_owned())
    }
  }
  let prefix = if path.has_prefix("//") {
    "//"
  } else if path.has_prefix("/") {
    "/"
  } else {
    ""
  }
  let result = prefix + parts.join("/")
  if drive_prefix(result) {
    result + "/"
  } else {
    result
  }
}

///|
fn within(path : String, base : String) -> String? {
  if path == base {
    return Some("")
  }
  let prefix = if base.has_suffix("/") { base } else { base + "/" }
  if path.has_prefix(prefix) {
    Some(path[prefix.length():].to_owned())
  } else {
    None
  }
}

///|
async fn optional_kind(path : String) -> @fs.FileKind? {
  try @fs.kind(path, follow_symlink=false) catch {
    @os_error.OSError(_) as e if e.is_ENOENT() => None
    e => raise e
  } noraise {
    kind => Some(kind)
  }
}

///|
// Resolve the deepest existing ancestor: output need not exist yet. No other
// filesystem errors (especially permission errors) are treated as absence.
async fn output_identity(path : String) -> String {
  if optional_kind(path) is Some(_) {
    return canonical(path)
  }
  let up = parent(path)
  if up == path {
    raise SelectionError::InvalidOutput(path)
  }
  join(output_identity(up), basename(path))
}

///|
fn utf8_compare(a : String, b : String) -> Int32 {
  let a = @utf8.encode(a)
  let b = @utf8.encode(b)
  for i in 0..<Int32::min(a.length(), b.length()) {
    let order = a[i].compare(b[i])
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}
