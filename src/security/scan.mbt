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
  scan_validated_text(path, text, bom_bytes)
}

///|
/// Scan the reader's strict-UTF-8 value without repeating UTF-16 validation.
/// All credential detectors and finding-coordinate checks still run unchanged.
pub fn scan_validated(
  path : String,
  validated : @validated_text.Text,
) -> Array[Finding] raise ScanError {
  scan_validated_text(path, validated.text(), validated.bom_bytes())
}

///|
fn scan_validated_text(
  path : String,
  text : String,
  bom_bytes : Int32,
) -> Array[Finding] raise ScanError {
  let hits = scan_credentials(text)
  if hits.is_empty() {
    return []
  }
  // Validate every engine range, including policy-filtered hits. Both entry
  // points have already established that the entire text is well-formed.
  let relevant : Array[(@moon_scrub.Finding, String)] = []
  for hit in hits {
    if hit.start < 0 ||
      hit.end <= hit.start ||
      hit.end > text.length() ||
      !scalar_boundary(text, hit.start) ||
      !scalar_boundary(text, hit.end) {
      raise InvalidEngineRange
    }
    if rule_for(text, hit) is Some(rule) {
      relevant.push((hit, rule))
    }
  }
  if relevant.is_empty() {
    return []
  }
  // Disk coordinates are needed only for policy-retained findings.
  let boundaries : Set[Int32] = Set([])
  let mut last_boundary = 0
  for (hit, _) in relevant {
    boundaries.add(hit.start)
    boundaries.add(hit.end)
    if hit.end > last_boundary {
      last_boundary = hit.end
    }
  }
  let coordinates : Map[Int32, (Int32, Int32)] = Map(
    [],
    capacity=boundaries.length(),
  )
  coordinates[0] = (bom_bytes, 1)
  let mut unit = 0
  let mut offset = bom_bytes
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
    if unit >= last_boundary {
      break
    }
  }
  let out : Array[Finding] = []
  for (hit, rule) in relevant {
    // An interior surrogate position has no entry and fails shut.
    guard coordinates.get(hit.start) is Some((start, hit_line)) else {
      raise InvalidEngineRange
    }
    guard coordinates.get(hit.end) is Some((end, _)) else {
      raise InvalidEngineRange
    }
    out.push({ rule, path, start, end, line: hit_line, })
  }
  out
}

///|
// On a previously validated UTF-16 string, only an interior low surrogate is
// not a scalar boundary. Out-of-range units fail before indexing the string.
fn scalar_boundary(text : String, unit : Int32) -> Bool {
  if unit < 0 || unit > text.length() {
    return false
  }
  if unit == text.length() {
    return true
  }
  let code = text[unit].to_int()
  code < 0xDC00 || code > 0xDFFF
}

///|
fn scan_credentials(text : String) -> Array[@moon_scrub.Finding] {
  // One conservative literal pass selects candidate families from the pinned
  // 0.5.2 inventory. Enabled detectors still receive the entire original text;
  // assignments/basic-auth, validation and overlap resolution are unchanged.
  let candidates = credential_candidates(text)
  let config = @moon_scrub.ScanConfig::secrets_only()
  @moon_scrub.scan_with_config(text, {
    ..config,
    detect_access_token: (candidates & 1) != 0,
    detect_bearer: (candidates & 2) != 0,
    detect_jwt: (candidates & 4) != 0,
    detect_private_key: (candidates & 8) != 0,
    detect_url_credential: (candidates & 16) != 0,
    detect_assignment: (candidates & 32) != 0,
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
