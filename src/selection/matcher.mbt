///|
/// A compiled root-relative file matcher. Empty patterns match no files.
/// Matching is pure; selection and security checks remain the caller's job.
struct FileMatcher {
  patterns : Array[Pattern]
}

///|
/// Compile the same bounded custom globs used for includes, without walking files.
pub fn file_matcher(
  patterns : Array[String],
) -> FileMatcher raise SelectionError {
  for pattern in patterns {
    if pattern.contains("\u0000") {
      raise InvalidPattern(
        source="keep-full",
        line=0,
        pattern~,
        detail="NUL is not supported",
      )
    }
  }
  { patterns: custom_patterns(patterns, "keep-full", root_relative=true), }
}

///|
/// Match a normalized root-relative file, including descendants of matched dirs.
pub fn FileMatcher::matches(self : FileMatcher, relative : String) -> Bool {
  if self.patterns.is_empty() ||
    relative.is_empty() ||
    relative.has_prefix("/") ||
    relative.contains("\\") ||
    relative.contains(":") ||
    relative.contains("\u0000") {
    return false
  }
  let parts = relative.split("/").map(part => part.to_owned()).to_array()
  if parts.any(part => part == "" || part == "." || part == "..") {
    return false
  }
  included_parts(self.patterns, parts[:])
}
