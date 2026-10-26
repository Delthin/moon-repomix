///|
priv struct ProcessedFile {
  file : @document.File
  stats : FileStats
  transform : Json?
}

///|
// Token acceptance is independent of completion order. The pipeline publishes
// these immutable results in the original selection order.
fn process_file_result(
  path : String,
  snapshot : @input.Snapshot,
  original_tokens : Int32,
  outcome : @compression.Outcome?,
  counter : @metrics.CountSession,
) -> ProcessedFile {
  let mut text = snapshot.text
  let mut tokens = original_tokens
  let mut transform : Json? = None
  if outcome is Some(result) {
    let compressed_tokens = if result.applied {
      counter.count(result.text)
    } else {
      original_tokens
    }
    let applied = result.applied && compressed_tokens < original_tokens
    if applied {
      text = result.text
      tokens = compressed_tokens
    }
    let ranges : Array[Json] = if applied {
      context_ranges(result.ranges)
    } else {
      []
    }
    let reason : Json = if result.applied && !applied {
      Json("not-fewer-tokens")
    } else {
      match result.reason {
        None => Json::null()
        Some(reason) => Json(reason)
      }
    }
    let language : Json = match result.language {
      None => Json::null()
      Some(name) => Json(name)
    }
    transform = Some({
      "path": path,
      "language": language,
      "applied": applied,
      "reason": reason,
      "ranges": ranges,
      "originalTokens": original_tokens,
      "outputTokens": tokens,
    })
  }
  {
    file: { path, text, },
    stats: { path, disk_bytes: snapshot.disk_bytes, tokens, original_tokens, },
    transform,
  }
}
