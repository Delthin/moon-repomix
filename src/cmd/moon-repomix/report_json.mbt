///|
fn report_style(style : @repomix.Style) -> String {
  match style {
    Xml => "xml"
    Markdown => "markdown"
    Json => "json"
    Plain => "plain"
  }
}

///|
fn report_security(status : @repomix.SecurityStatus, findings : Int32) -> Json {
  let name = match status {
    Passed => "passed"
    Excluded => "excluded"
    Disabled => "disabled"
  }
  { "status": name, "enabled": !(status is Disabled), "findings": findings }
}

///|
fn report_limit(limit : Int32?) -> Json {
  match limit {
    None => Json::null()
    Some(value) => Json(value.to_string())
  }
}

///|
fn single_report(
  result : @repomix.PackResult,
  options : @config.Options,
) -> Json {
  let exceeded = result.budget is Exceeded(_)
  {
    "schemaVersion": 1,
    "status": if exceeded {
      "over_budget"
    } else {
      "ok"
    },
    "operation": "pack",
    "publication": "committed",
    "exitCode": if exceeded {
      1
    } else {
      0
    },
    "style": report_style(options.style),
    "security": report_security(result.security, result.findings.length()),
    "counts": {
      "acceptedFiles": result.files.length(),
      "skippedEntries": result.skipped.length(),
    },
    "output": {
      "kind": if options.stdout {
        "stdout"
      } else {
        "file"
      },
      "documents": 1,
    },
    "tokens": {
      "documents": result.tokens.to_string(),
      "index": "0",
      "total": result.tokens.to_string(),
      "limit": report_limit(options.token_budget),
      "exceeded": exceeded,
    },
    "bytes": {
      "documents": result.bytes.to_string(),
      "index": "0",
      "total": result.bytes.to_string(),
    },
  }
}

///|
fn volumes_report(
  result : @repomix.VolumePackResult,
  options : @config.Options,
  cap : Int32,
) -> Json {
  let mut tokens = 0L
  let mut bytes = 0L
  let rows : Array[Json] = []
  for volume in result.partition.volumes {
    tokens += volume.tokens.to_int64()
    bytes += volume.bytes.to_int64()
    rows.push({
      "id": volume.id,
      "fileName": result.file_names[volume.id],
      "tokens": volume.tokens.to_string(),
      "bytes": volume.bytes.to_string(),
      "files": volume.file_indices.length(),
      "sections": volume.section_indices.length(),
    })
  }
  let index_bytes = @utf8.encode(result.partition.index_text)
    .length()
    .to_int64()
  {
    "schemaVersion": 1,
    "status": "ok",
    "operation": "volumes",
    "publication": "committed",
    "exitCode": 0,
    "style": report_style(options.style),
    "security": report_security(result.security, result.findings.length()),
    "counts": {
      "acceptedFiles": result.files.length(),
      "skippedEntries": result.skipped.length(),
    },
    "output": {
      "kind": "directory",
      "documents": result.partition.volumes.length(),
      "indexFile": "index.json",
    },
    "tokens": {
      "documents": tokens.to_string(),
      "index": result.partition.index_tokens.to_string(),
      "total": result.partition.total_tokens.to_string(),
      "limit": cap.to_string(),
      "exceeded": false,
    },
    "bytes": {
      "documents": bytes.to_string(),
      "index": index_bytes.to_string(),
      "total": (bytes + index_bytes).to_string(),
    },
    "volumes": rows,
  }
}

///|
fn error_report(
  category : String,
  field : String?,
  limit : Int64?,
  publication : String,
) -> Json {
  {
    "schemaVersion": 1,
    "status": "error",
    "exitCode": 1,
    "publication": publication,
    "error": {
      "category": category,
      "field": match field {
        None => Json::null()
        Some(value) => Json(value)
      },
      "limit": match limit {
        None => Json::null()
        Some(value) => Json(value.to_string())
      },
    },
  }
}

///|
async fn write_json_report(value : Json) -> Unit {
  @stdio.stderr.write(value.stringify() + "\n")
}
