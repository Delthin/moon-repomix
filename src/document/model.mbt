///|
/// An accepted immutable snapshot. Files are ordered by UTF-8 relative path bytes.
pub(all) struct File {
  path : String
  text : String
}

///|
/// Additional untrusted repository context, such as a diff or commit message.
pub(all) struct Section {
  kind : String
  title : String
  text : String
}

///|
pub(all) struct Document {
  files : Array[File]
  sections : Array[Section]
  metadata : Json
}

///|
pub fn compare_path(a : String, b : String) -> Int32 {
  @utf8.encode(a).lexical_compare(@utf8.encode(b))
}

///|
/// Sort once before rendering so every output shares the same order.
pub fn create(
  files : Array[File],
  sections~ : Array[Section] = [],
  metadata~ : Json = Json::null(),
) -> Document {
  let sorted = files.copy()
  sorted.sort_by((a, b) => compare_path(a.path, b.path))
  { files: sorted, sections, metadata, }
}

///|
/// A deterministic directory outline containing accepted files only.
pub fn tree(document : Document) -> String {
  let lines : Array[String] = []
  let directories : Set[String] = Set([])
  for file in document.files {
    let parts = file.path.split("/").to_array()
    let mut prefix = ""
    for i in 0..<parts.length() {
      let part = parts[i].to_owned()
      prefix = if prefix == "" { part } else { prefix + "/" + part }
      let leaf = i == parts.length() - 1
      if leaf || !directories.contains(prefix) {
        lines.push("  ".repeat(i) + part + (if leaf { "" } else { "/" }))
        if !leaf {
          directories.add(prefix)
        }
      }
    }
  }
  lines.join("\n")
}
