///|
pub(all) struct Definition {
  name : String
  qualified_name : String
  start_byte : Int32
  end_byte : Int32
  start_line : Int32
  end_line : Int32
  references : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct DefinitionIndex {
  definitions : Array[Definition]
  reason : String?
} derive(Debug, Eq)

///|
pub extend Definition with Eq::{equal, not_equal}

///|
pub extend Definition with Debug::{to_repr}

///|
pub extend DefinitionIndex with Eq::{equal, not_equal}

///|
pub extend DefinitionIndex with Debug::{to_repr}

///|
#borrow(source)
extern "c" fn definition_index(language : Int32, source : Bytes) -> Bytes = "moon_repomix_definition_index"

///|
/// Return a fresh array of all suffixes supported by `index_definitions`.
/// Suffixes are lowercase, dot-prefixed and matched case-insensitively.
pub fn definition_extensions() -> Array[String] {
  [
    ".js", ".jsx", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".tsx", ".py", ".pyi",
    ".mbt", ".mbti",
  ]
}

///|
/// Index complete definitions, not compressed signatures, without I/O.
/// Supports exactly `definition_extensions()` using vendored native ASTs.
/// Bytes are 0-based UTF-8 [start, end); lines are 1-based inclusive.
/// Duplicate names remain separate entries; references are lexical candidates.
/// MoonBit names use Type::method, Trait::method and Trait for Type::method.
/// Trait methods retain the whole trait; nested definitions stay in their outer
/// definition and are not promoted into independent global entries.
/// References are deduplicated lexical identifier uses, not a resolved call graph.
/// Any parse/timeout/resource failure returns an empty array and a reason.
///
/// ```mbt check
/// test {
///   let index = @compression.index_definitions(
///     "sample.js", "const LIMIT = 3;\nfunction size() { return LIMIT; }",
///   )
///   assert_eq(index.reason, None)
///   assert_eq(index.definitions[1].references, ["LIMIT"])
/// }
/// ```
pub fn index_definitions(path : String, text : String) -> DefinitionIndex {
  let lower = path.to_lower()
  guard definition_extensions().any(extension => lower.has_suffix(extension)) &&
    detect(path) is Some((language, _)) else {
    return { definitions: [], reason: Some("unsupported-language"), }
  }
  // UTF-8 is at least as long as UTF-16 in code units. Reject huge Strings
  // before encoding, then apply the exact byte limit as well.
  if text.length() > 8 * 1024 * 1024 {
    return { definitions: [], reason: Some("resource-limit"), }
  }
  let source = @utf8.encode(text)
  if source.length() > 8 * 1024 * 1024 {
    return { definitions: [], reason: Some("resource-limit"), }
  }
  let wire = definition_index(language, source)
  let reason = match u32(wire, 0) {
    0 => None
    1 => Some("parse-error")
    2 => Some("timeout")
    3 => Some("resource-limit")
    6 => Some("unsupported-language")
    _ => Some("parser-unavailable")
  }
  if reason is Some(_) {
    return { definitions: [], reason, }
  }
  let definitions : Array[Definition] = []
  let mut offset = 8
  for _ in 0..<u32(wire, 4) {
    let start_byte = u32(wire, offset)
    let end_byte = u32(wire, offset + 4)
    let start_line = u32(wire, offset + 8)
    let end_line = u32(wire, offset + 12)
    let name_length = u32(wire, offset + 16)
    let qualified_length = u32(wire, offset + 20)
    let ref_count = u32(wire, offset + 24)
    offset += 28
    let name = @utf8.decode_lossy(wire[offset:offset + name_length])
    offset += name_length
    let qualified_name = @utf8.decode_lossy(
      wire[offset:offset + qualified_length],
    )
    offset += qualified_length
    let references : Array[String] = []
    for _ in 0..<ref_count {
      let length = u32(wire, offset)
      offset += 4
      references.push(@utf8.decode_lossy(wire[offset:offset + length]))
      offset += length
    }
    definitions.push({
      name,
      qualified_name,
      start_byte,
      end_byte,
      start_line,
      end_line,
      references,
    })
  }
  { definitions, reason: None, }
}
