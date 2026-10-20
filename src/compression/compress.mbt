///|
#borrow(source)
extern "c" fn structure_plan(language : Int32, source : Bytes) -> Bytes = "moon_repomix_structure_plan"

///|
fn u32(bytes : Bytes, offset : Int32) -> Int32 {
  bytes[offset].to_int() |
  (bytes[offset + 1].to_int() << 8) |
  (bytes[offset + 2].to_int() << 16) |
  (bytes[offset + 3].to_int() << 24)
}

///|
fn omission(
  builder : StringBuilder,
  source : Bytes,
  start : Int32,
  end : Int32,
  marker : String,
) -> Unit {
  // AST-selected presentation whitespace needs no synthetic omission marker.
  let mut only_space = true
  for i in start..<end {
    if source[i] != b' ' &&
      source[i] != b'\t' &&
      source[i] != b'\r' &&
      source[i] != b'\n' {
      only_space = false
      break
    }
  }
  if only_space {
    return
  }
  if start == 0 || source[start - 1] == b'\n' {
    let mut indent_end = start
    while indent_end < end &&
          (source[indent_end] == b' ' || source[indent_end] == b'\t') {
      indent_end += 1
    }
    builder.write_string(@utf8.decode_lossy(source[start:indent_end]))
  }
  builder.write_string(marker)
  if end > start && source[end - 1] == b'\n' {
    builder.write_string(
      if end > start + 1 && source[end - 2] == b'\r' {
        "\r\n"
      } else {
        "\n"
      },
    )
  }
}

///|
fn detect(path : String) -> (Int32, String)? {
  let name = path.to_lower()
  if name.has_suffix(".tsx") {
    Some((2, "tsx"))
  } else if name.has_suffix(".ts") ||
    name.has_suffix(".mts") ||
    name.has_suffix(".cts") {
    Some((1, "typescript"))
  } else if name.has_suffix(".js") ||
    name.has_suffix(".jsx") ||
    name.has_suffix(".mjs") ||
    name.has_suffix(".cjs") {
    Some((0, "javascript"))
  } else if name.has_suffix(".py") || name.has_suffix(".pyi") {
    Some((3, "python"))
  } else {
    None
  }
}

///|
fn fallback(text : String, language : String?, reason : String) -> Outcome {
  { text, language, applied: false, reason: Some(reason), ranges: [], }
}

///|
/// Compress JavaScript/JSX, TypeScript/TSX or Python into a source-ordered AST
/// outline. Implementations become synthetic `/* … */` (JS/TS) or `...`
/// (Python) markers. This is context text, not executable source.
///
/// Stable fallback reasons: unsupported, parse-error, not-smaller, timeout,
/// resource-limit, parser-unavailable. Parse budget: 200 ms per file; input
/// limit: 8 MiB UTF-8. The caller performs raw-source security scanning first.
pub fn compress(path : String, text : String) -> Outcome {
  guard detect(path) is Some((id, language)) else {
    return fallback(text, None, "unsupported")
  }
  let source = @utf8.encode(text)
  if source.length() > 8 * 1024 * 1024 {
    return fallback(text, Some(language), "resource-limit")
  }
  let plan = structure_plan(id, source)
  let reason = match u32(plan, 0) {
    0 => None
    1 => Some("parse-error")
    2 => Some("timeout")
    3 => Some("resource-limit")
    _ => Some("parser-unavailable")
  }
  if reason is Some(reason) {
    return fallback(text, Some(language), reason)
  }
  let builder = StringBuilder()
  let ranges : Array[LineRange] = []
  let marker = if id == 3 { "..." } else { "/* … */" }
  let mut previous_end = 0
  for offset = 4; offset < plan.length(); offset = offset + 16 {
    let start = u32(plan, offset)
    let end = u32(plan, offset + 4)
    if start > previous_end {
      omission(builder, source, previous_end, start, marker)
    }
    builder.write_string(@utf8.decode_lossy(source[start:end]))
    ranges.push({
      start_line: u32(plan, offset + 8),
      end_line: u32(plan, offset + 12),
    })
    previous_end = end
  }
  if previous_end < source.length() {
    omission(builder, source, previous_end, source.length(), marker)
  }
  let result = builder.to_string()
  if ranges.is_empty() || @utf8.encode(result).length() >= source.length() {
    return fallback(text, Some(language), "not-smaller")
  }
  {
    text: result,
    language: Some(language),
    applied: true,
    reason: None,
    ranges,
  }
}
