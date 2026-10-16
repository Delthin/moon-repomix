///|
/// Locations refer to the original disk UTF-8 bytes, including a stripped BOM.
pub(all) struct Finding {
  rule : String
  path : String
  start : Int32
  end : Int32
  line : Int32
} derive(Debug, Eq)

///|
pub extend Finding with Eq::{equal, not_equal}

///|
pub extend Finding with Debug::{to_repr}

///|
/// Stable categories only: neither text, paths nor engine diagnostics are stored.
pub(all) suberror ScanError {
  InvalidBomOffset
  InvalidText
  InvalidEngineRange
  InputTooLarge
} derive(Debug, Eq)

///|
pub extend ScanError with Eq::{equal, not_equal}

///|
pub extend ScanError with Debug::{to_repr}

///|
/// Scan a snapshot using moon_scrub's secrets-only policy. Pass 3 only when
/// the reader removed a UTF-8 BOM; otherwise pass 0. A finding excludes the
/// entire file at the caller, not just its byte range.
///
/// ```mbt check
/// test {
///   assert_eq(@security.scan("readme.md", "hello", 0).length(), 0)
/// }
/// ```
pub fn scan(
  path : String,
  text : String,
  bom_bytes : Int32,
) -> Array[Finding] raise ScanError {
  if bom_bytes != 0 && bom_bytes != 3 {
    raise InvalidBomOffset
  }
  // moon_scrub 0.5.2 walks String.length()/text[i]: UTF-16 code units.
  // Interior surrogate positions stay -1, so an invalid engine range fails shut.
  let bytes = Array::make(text.length() + 1, -1)
  let lines = Array::make(text.length() + 1, 1)
  let mut unit = 0
  let mut offset = bom_bytes
  let mut line = 1
  let mut previous_cr = false
  bytes[0] = offset
  for c in text {
    let cp = c.to_int()
    if cp >= 0xD800 && cp <= 0xDFFF {
      raise InvalidText
    }
    let width = if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    if offset > 2147483647 - width {
      raise InputTooLarge
    }
    offset += width
    unit += if cp > 0xFFFF { 2 } else { 1 }
    if c == '\r' || (c == '\n' && !previous_cr) {
      line += 1
    }
    previous_cr = c == '\r'
    bytes[unit] = offset
    lines[unit] = line
  }
  let out : Array[Finding] = []
  for
    hit in @moon_scrub.scan_with_config(
      text,
      @moon_scrub.ScanConfig::secrets_only(),
    ) {
    if hit.start < 0 ||
      hit.end <= hit.start ||
      hit.end > text.length() ||
      bytes[hit.start] < 0 ||
      bytes[hit.end] < 0 {
      raise InvalidEngineRange
    }
    if rule_for(text, hit) is Some(rule) {
      out.push({
        rule,
        path,
        start: bytes[hit.start],
        end: bytes[hit.end],
        line: lines[hit.start],
      })
    }
  }
  out
}
