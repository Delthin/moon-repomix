///|
/// Decode a literal file list without trimming filenames or interpreting globs.
/// LF mode accepts CRLF; NUL mode preserves all CR/LF characters in a filename.
/// Empty records are skipped. `Some([])` remains an explicitly empty selection.
/// The selection package validates paths and applies all exclusion layers.
pub fn parse_file_list(
  text : String,
  nul~ : Bool = false,
) -> Array[String] raise ConfigError {
  let text = if text.has_prefix("\uFEFF") { text[1:].to_owned() } else { text }
  let result : Array[String] = []
  for entry in text.split(if nul { "\u0000" } else { "\n" }) {
    let mut path = entry.to_owned()
    if !nul && path.has_suffix("\r") {
      path = path[:path.length() - 1].to_owned()
    }
    if path == "" {
      continue
    }
    if path.contains("\u0000") {
      raise InvalidValue("stdin")
    }
    result.push(path)
  }
  result
}
