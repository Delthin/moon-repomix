///|
// Keep token acceptance, metadata and file statistics identical for serial and
// worker-produced outlines. Call in the original selection order.
fn record_file_result(
  path : String,
  snapshot : @input.Snapshot,
  original_tokens : Int32,
  outcome : @compression.Outcome?,
  runtime : Runtime,
  accepted : Array[@document.File],
  files : Array[FileStats],
  transforms : Array[Json],
) -> Unit {
  let mut text = snapshot.text
  let mut tokens = original_tokens
  if outcome is Some(result) {
    let compressed_tokens = if result.applied {
      runtime.encoder.count(result.text)
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
    transforms.push({
      "path": path,
      "language": language,
      "applied": applied,
      "reason": reason,
      "ranges": ranges,
      "originalTokens": original_tokens,
      "outputTokens": tokens,
    })
  }
  accepted.push({ path, text, })
  files.push({ path, disk_bytes: snapshot.disk_bytes, tokens, original_tokens, })
}
