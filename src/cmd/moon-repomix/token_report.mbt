///|
fn compare_report_path(a : String, b : String) -> Int32 {
  @utf8.encode(a).lexical_compare(@utf8.encode(b))
}

///|
fn top_files(files : Array[@repomix.FileStats], limit : Int32) -> String {
  if limit == 0 || files.is_empty() {
    return ""
  }
  let sorted = files.copy()
  sorted.sort_by((a, b) => {
    if a.tokens > b.tokens {
      -1
    } else if a.tokens < b.tokens {
      1
    } else {
      compare_report_path(a.path, b.path)
    }
  })
  let count = Int32::min(limit, sorted.length())
  let lines = [
    "Top files by content tokens (showing \{count} of \{files.length()}):",
  ]
  for i in 0..<count {
    let file = sorted[i]
    lines.push(
      "  \{i + 1}. " +
      quote(file.path) +
      ": \{file.tokens} tokens (\{file.disk_bytes} bytes)",
    )
  }
  lines.join("\n") + "\n"
}

///|
priv struct TokenDirectory {
  mut tokens : Int64
  files : Array[@repomix.FileStats]
  children : Map[String, TokenDirectory]
}

///|
fn TokenDirectory::new() -> TokenDirectory {
  { tokens: 0L, files: [], children: Map([]), }
}

///|
fn token_tree_lines(
  directory : TokenDirectory,
  threshold : Int64,
  prefix : String,
  lines : Array[String],
) -> Unit {
  let files = directory.files.filter(file => file.tokens.to_int64() >= threshold)
  files.sort_by((a, b) => compare_report_path(a.path, b.path))
  let children : Array[(String, TokenDirectory)] = []
  for name, child in directory.children {
    if child.tokens >= threshold {
      children.push((name, child))
    }
  }
  children.sort_by((a, b) => compare_report_path(a.0, b.0))
  for i in 0..<files.length() {
    let file = files[i]
    let parts = file.path.split("/").to_array()
    let last = i == files.length() - 1 && children.is_empty()
    lines.push(
      prefix +
      (if last { "└── " } else { "├── " }) +
      quote(parts[parts.length() - 1].to_owned()) +
      " (\{file.tokens} tokens)",
    )
  }
  for i in 0..<children.length() {
    let (name, child) = children[i]
    let last = i == children.length() - 1
    lines.push(
      prefix +
      (if last { "└── " } else { "├── " }) +
      quote(name + "/") +
      " (\{child.tokens} tokens)",
    )
    token_tree_lines(
      child,
      threshold,
      prefix + (if last { "    " } else { "│   " }),
      lines,
    )
  }
}

///|
/// Only accepted snapshots contribute. Filtering never changes directory sums.
fn token_tree(files : Array[@repomix.FileStats], threshold : Int32) -> String {
  let root = TokenDirectory::new()
  for file in files {
    let tokens = file.tokens.to_int64()
    let parts = file.path.split("/").to_array()
    let mut directory = root
    directory.tokens += tokens
    for i in 0..<(parts.length() - 1) {
      let name = parts[i].to_owned()
      let child = match directory.children.get(name) {
        Some(child) => child
        None => {
          let child = TokenDirectory::new()
          directory.children[name] = child
          child
        }
      }
      child.tokens += tokens
      directory = child
    }
    directory.files.push(file)
  }
  let lines = [
    "Token count tree (content tokens; directory sums; minimum \{threshold}):",
    ". (\{root.tokens} tokens)",
  ]
  token_tree_lines(root, threshold.to_int64(), "", lines)
  if lines.length() == 2 {
    lines.push(
      if files.is_empty() {
        "No accepted files."
      } else {
        "No files or directories with at least \{threshold} tokens."
      },
    )
  }
  lines.join("\n") + "\n"
}
