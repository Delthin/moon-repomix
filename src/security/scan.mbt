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
  // Validate before running the engine, retaining the public error contract.
  let mut offset = bom_bytes
  for c in text {
    let cp = c.to_int()
    if cp >= 0xD800 && cp <= 0xDFFF {
      raise InvalidText
    }
    let width = scalar_utf8_bytes(cp)
    if offset > 2147483647 - width {
      raise InputTooLarge
    }
    offset += width
  }
  let hits = scan_credentials(text)
  if hits.is_empty() {
    return []
  }
  // moon_scrub uses UTF-16 offsets. Only hit boundaries need disk coordinates;
  // clean files never allocate a per-code-unit byte/line table.
  let boundaries : Set[Int32] = Set([])
  for hit in hits {
    if hit.start < 0 || hit.end <= hit.start || hit.end > text.length() {
      raise InvalidEngineRange
    }
    boundaries.add(hit.start)
    boundaries.add(hit.end)
  }
  let coordinates : Map[Int32, (Int32, Int32)] = Map(
    [],
    capacity=boundaries.length(),
  )
  coordinates[0] = (bom_bytes, 1)
  let mut unit = 0
  offset = bom_bytes
  let mut line = 1
  let mut previous_cr = false
  for c in text {
    let cp = c.to_int()
    offset += scalar_utf8_bytes(cp)
    unit += if cp > 0xFFFF { 2 } else { 1 }
    if c == '\r' || (c == '\n' && !previous_cr) {
      line += 1
    }
    previous_cr = c == '\r'
    if boundaries.contains(unit) {
      coordinates[unit] = (offset, line)
    }
  }
  let out : Array[Finding] = []
  for hit in hits {
    // An interior surrogate position has no entry and fails shut.
    guard coordinates.get(hit.start) is Some((start, hit_line)) else {
      raise InvalidEngineRange
    }
    guard coordinates.get(hit.end) is Some((end, _)) else {
      raise InvalidEngineRange
    }
    if rule_for(text, hit) is Some(rule) {
      out.push({ rule, path, start, end, line: hit_line, })
    }
  }
  out
}

///|
fn scan_credentials(text : String) -> Array[@moon_scrub.Finding] {
  // All seven private-key headers in pinned moon_scrub 0.5.2 contain this
  // exact, case-sensitive prefix. Its absence proves that this family cannot
  // produce a finding; the full text still reaches every other detector.
  let config = @moon_scrub.ScanConfig::secrets_only()
  @moon_scrub.scan_with_config(text, {
    ..config,
    detect_private_key: text.contains("-----BEGIN "),
  })
}

///|
fn scalar_utf8_bytes(cp : Int32) -> Int32 {
  if cp < 0x80 {
    1
  } else if cp < 0x800 {
    2
  } else if cp < 0x10000 {
    3
  } else {
    4
  }
}
