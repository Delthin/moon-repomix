///|
fn relative_file_path(path : String) -> Bool {
  path != "" &&
  !absolute(path) &&
  !path.contains("\u{0}") &&
  !path.split("/").any(p => p == "" || p == "." || p == "..")
}

///|
// Exact inputs use portable '/' spelling even on Unix. Never normalize away an
// invalid component, trim whitespace, or interpret wildcard/brace characters.
fn exact_paths(
  file_paths : Array[String]?,
) -> Array[String]? raise SelectionError {
  guard file_paths is Some(paths) else { return None }
  let unique : Map[String, Bool] = Map([])
  let result : Array[String] = []
  for path in paths {
    if !relative_file_path(path) || path.contains("\\") || path.contains(":") {
      raise invalid_pattern(
        "file_paths", 0, path, "expected a literal root-relative file path with '/' separators and no empty, '.' or '..' components, NUL, backslash or colon",
      )
    }
    if !unique.contains(path) {
      unique[path] = true
      result.push(path)
    }
  }
  result.sort_by(utf8_compare)
  Some(result)
}
