///|
// Render an overview by default without changing the complete Document model.
// All formats expose the original records with full_metadata.
fn render_metadata(metadata : Json, full_metadata : Bool) -> Json {
  if full_metadata {
    return metadata
  }
  guard metadata is Object(original) else { return metadata }
  let fields = original.copy()
  if fields.get("compression") is Some(value) {
    let summary = compression_summary(value)
    if summary == Json::null() {
      fields.remove("compression")
    } else {
      fields["compression"] = summary
    }
  }
  match fields.get("git") {
    Some(Null) => fields.remove("git")
    Some({ "diffs": Array(diffs), "commits": Array(commits), .. }) =>
      if diffs.is_empty() && commits.is_empty() {
        fields.remove("git")
      } else {
        fields["git"] = { "diffs": diffs.length(), "commits": commits.length() }
      }
    _ => ()
  }
  Json(fields)
}

///|
fn compression_summary(value : Json) -> Json {
  guard value is Array(records) else { return value }
  if records.is_empty() {
    return Json::null()
  }
  let mut applied_count = 0
  let mut original_tokens = 0L
  let mut output_tokens = 0L
  let languages : Map[String, Int32] = Map([])
  let fallbacks : Map[String, Int32] = Map([])
  for record in records {
    guard record
      is {
        "applied": applied,
        "originalTokens": Number(original, ..),
        "outputTokens": Number(output, ..),
        ..
      } else {
      // Custom Document metadata need not use the packer's schema.
      return value
    }
    if !(original >= 0 &&
      original <= 2147483647.0 &&
      original.to_int().to_double() == original &&
      output >= 0 &&
      output <= 2147483647.0 &&
      output.to_int().to_double() == output) {
      return value
    }
    original_tokens += original.to_int().to_int64()
    output_tokens += output.to_int().to_int64()
    match applied {
      True => applied_count += 1
      False => {
        let reason = match record {
          { "reason": String(reason), .. } => reason
          _ => "unknown"
        }
        fallbacks[reason] = fallbacks.get(reason).unwrap_or(0) + 1
      }
      _ => return value
    }
    if record is { "language": String(language), .. } {
      languages[language] = languages.get(language).unwrap_or(0) + 1
    }
  }
  // Preserve exact numbers even for custom Documents with oversized counts.
  if original_tokens > 9007199254740991L || output_tokens > 9007199254740991L {
    return value
  }
  {
    "files": records.length(),
    "applied": applied_count,
    "originalTokens": original_tokens.to_double(),
    "outputTokens": output_tokens.to_double(),
    "languages": languages,
    "fallbacks": fallbacks,
  }
}
