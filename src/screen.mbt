///|
fn validate_source_limits(options : Options) -> Unit raise PackError {
  if options.max_file_size <= 0 ||
    options.max_files < 0 ||
    options.max_total_size < 0 ||
    options.max_total_size > 9007199254740991L {
    raise ConfigurationError
  }
}

///|
priv struct ScreenedRead {
  result : @input.ReadResult
  findings : Array[Finding]
  read_bytes : Int64
}

///|
// One source of truth for pack and query-level explanation. No body is returned
// for skipped input; read accounting includes bytes rejected by later stages.
async fn read_screened(
  candidate : @selection.Candidate,
  options : Options,
  remaining : Int64,
) -> ScreenedRead {
  let metered = @input.read_metered(
    candidate.path,
    options.max_file_size,
    remaining,
  ) catch {
    @input.TotalSizeLimitExceeded =>
      raise InputLimitExceeded(
        kind="maxTotalSize",
        limit=options.max_total_size,
      )
    err => raise err
  }
  guard metered.result is Loaded(snapshot) else {
    return {
      result: metered.result,
      findings: [],
      read_bytes: metered.read_bytes,
    }
  }
  if options.security_check {
    let findings = @security.scan(
      candidate.relative,
      snapshot.text,
      snapshot.bom_bytes,
    ) catch {
      _ => raise ScanError
    }
    if !findings.is_empty() {
      return {
        result: @input.Skipped("SecurityFinding"),
        findings,
        read_bytes: metered.read_bytes,
      }
    }
  }
  if options.style is Xml &&
    (
      !@output.xml_representable(candidate.relative) ||
      !@output.xml_representable(snapshot.text)
    ) {
    return {
      result: @input.Skipped("UnrepresentableText"),
      findings: [],
      read_bytes: metered.read_bytes,
    }
  }
  { result: metered.result, findings: [], read_bytes: metered.read_bytes, }
}
