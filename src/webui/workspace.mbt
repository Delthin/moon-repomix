///|
fn contained(root : String, path : String) -> Bool {
  path == root ||
  path.has_prefix(if root.has_suffix("/") { root } else { root + "/" })
}

///|
async fn canonical_root(path : String) -> String {
  let mut path = @platform.separators(path)
  // Trailing '/.' or '/' must not conceal a linked final component.
  while path.length() > 1 {
    if path.has_suffix("/.") {
      path = path[:-2].to_owned()
    } else if path.has_suffix("/") && !(path.length() == 3 && path[1] == ':') {
      path = path[:-1].to_owned()
    } else {
      break
    }
  }
  guard @fs.kind(path, follow_symlink=false) is Directory else {
    raise PublicError(
      403, "invalid_workspace", "Workspace must be a non-linked local directory.",
    )
  }
  @platform.separators(@fs.realpath(path))
}

///|
async fn scoped_directory(root : String, relative : String) -> String {
  validate_relative(relative)
  if relative == "." {
    return root
  }
  let mut current = root
  for component in relative.split("/") {
    current = @platform.join(current, component.to_owned())
    guard @fs.kind(current, follow_symlink=false) is Directory else {
      raise PublicError(
        403, "directory_not_allowed", "Directory is not available in this workspace.",
      )
    }
    let real = @platform.separators(@fs.realpath(current))
    if !contained(root, real) {
      raise PublicError(
        403, "directory_not_allowed", "Directory is not available in this workspace.",
      )
    }
  }
  current
}

///|
fn hidden_directory(name : String) -> Bool {
  name.has_prefix(".") ||
  [
    "node_modules", "_build", "target", "dist", "build", "vendor", "coverage", "__pycache__",
  ].contains(name)
}

///|
async fn directories(state : State, value : Json) -> Json {
  let relative = directory_field(fields(value, ["directory"]))
  let path = scoped_directory(state.options.directory, relative)
  let names = @fs.readdir(path, include_hidden=false)
  names.sort()
  let children : Array[String] = []
  for name in names {
    if hidden_directory(name) {
      continue
    }
    validate_relative(name)
    let child = @platform.join(path, name)
    if @fs.kind(child, follow_symlink=false) is Directory {
      let real = @platform.separators(@fs.realpath(child))
      if contained(state.options.directory, real) {
        children.push(
          if relative == "." {
            name
          } else {
            relative + "/" + name
          },
        )
        if children.length() == 200 {
          break
        }
      }
    }
  }
  { "directory": relative, "directories": Json(children) }
}

///|
async fn static_text(resource : String, name : String) -> String {
  let root = @platform.join(@platform.parent(resource), "webui")
  // Only fixed names reach this function. Reject links for both the directory
  // and the leaf; never expose the tokenizer or a directory listing.
  guard @fs.kind(root, follow_symlink=false) is Directory else {
    raise PublicError(
      500, "assets_unavailable", "Web UI assets are unavailable.",
    )
  }
  let real_root = @platform.separators(@fs.realpath(root))
  let path = @platform.join(root, name)
  guard @fs.kind(path, follow_symlink=false) is Regular else {
    raise PublicError(
      500, "assets_unavailable", "Web UI assets are unavailable.",
    )
  }
  if !contained(real_root, @platform.separators(@fs.realpath(path))) {
    raise PublicError(
      500, "assets_unavailable", "Web UI assets are unavailable.",
    )
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.size() > 2097152L {
    raise PublicError(
      500, "assets_unavailable", "Web UI assets are unavailable.",
    )
  }
  file.read_all().text()
}
