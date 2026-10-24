///|
priv suberror PublicError {
  PublicError(Int32, String, String)
}

///|
fn invalid() -> Unit raise {
  raise PublicError(400, "invalid_request", "Invalid request.")
}

///|
fn fields(value : Json, allowed : Array[String]) -> Map[String, Json] raise {
  guard value is Object(values) else {
    invalid()
    return Map([])
  }
  for key, _ in values {
    if !allowed.contains(key) {
      invalid()
    }
  }
  values
}

///|
fn directory_field(values : Map[String, Json]) -> String raise {
  guard values.get("directory") is Some(String(directory)) else {
    invalid()
    return ""
  }
  validate_relative(directory)
  directory
}

///|
fn validate_relative(path : String) -> Unit raise {
  if path == "." {
    return
  }
  if path.is_empty() ||
    path.contains("\\") ||
    path.contains(":") ||
    path.contains("\u0000") {
    invalid()
  }
  for part in path.split("/") {
    if part == "" || part == "." || part == ".." {
      invalid()
    }
  }
}

///|
priv struct PackRequest {
  directory : String
  profile : String
  budget : Int32
  includes : Array[String]
  keep_full : Array[String]
}

///|
fn patterns(values : Map[String, Json], key : String) -> Array[String] raise {
  guard values.get(key) is Some(Array(items)) else {
    invalid()
    return []
  }
  if items.length() > 64 {
    invalid()
  }
  let result : Array[String] = []
  for item in items {
    guard item is String(pattern) else {
      invalid()
      continue
    }
    if @utf8.encode(pattern).length() > 1024 {
      invalid()
    }
    result.push(pattern)
  }
  // Reuse the product's glob validation, including traversal restrictions.
  ignore(
    @config.parse_json(Json::object({ "include": Json(result) }).stringify()) catch {
      _ => raise PublicError(400, "invalid_patterns", "Invalid patterns.")
    },
  )
  ignore(
    @selection.file_matcher(result) catch {
      _ => raise PublicError(400, "invalid_patterns", "Invalid patterns.")
    },
  )
  result
}

///|
fn pack_request(value : Json) -> PackRequest raise {
  let values = fields(value, [
    "directory", "profile", "tokenBudget", "includePatterns", "keepFull",
  ])
  let directory = directory_field(values)
  guard values.get("profile") is Some(String(profile)) &&
    (profile == "raw" || profile == "skeleton" || profile == "mixed") else {
    invalid()
    return { directory, profile: "", budget: 1, includes: [], keep_full: [], }
  }
  guard values.get("tokenBudget") is Some(Number(n, ..)) &&
    n > 0 &&
    n <= 2147483647.0 &&
    n.to_int().to_double() == n else {
    invalid()
    return { directory, profile, budget: 1, includes: [], keep_full: [], }
  }
  let includes = patterns(values, "includePatterns")
  let keep_full = patterns(values, "keepFull")
  if includes.length() + keep_full.length() > 64 {
    invalid()
  }
  { directory, profile, budget: n.to_int(), includes, keep_full, }
}

///|
fn authorize(request : @http.Request, port : Int32) -> Unit raise {
  let authority = "127.0.0.1:" + port.to_string()
  if request.headers.get("host") != Some(authority) {
    raise PublicError(403, "forbidden_host", "Host is not allowed.")
  }
  if request.headers.get("origin") is Some(origin) &&
    origin != "http://" + authority {
    raise PublicError(403, "forbidden_origin", "Origin is not allowed.")
  }
  if request.meth is Options {
    raise PublicError(
      403, "forbidden_preflight", "Cross-origin requests are not allowed.",
    )
  }
  if request.path.has_prefix("/api/") &&
    request.headers.get("x-moon-repomix") != Some("webui") {
    raise PublicError(
      403, "missing_client_header", "Web UI client header is required.",
    )
  }
  if request.meth is Post {
    let content_type = request.headers.get("content-type").unwrap_or("")
    let media = content_type
      .split(";")
      .next()
      .unwrap_or("")
      .trim()
      .to_owned()
      .to_lower()
    if media != "application/json" {
      raise PublicError(
        400, "invalid_content_type", "JSON content type is required.",
      )
    }
  }
}

///|
async fn read_json(body : &@io.Reader) -> Json {
  let buffer = Buffer()
  while body.read_some(max_len=8192) is Some(chunk) {
    if chunk.length() > 65536 - buffer.length() {
      raise PublicError(413, "body_too_large", "Request body exceeds 64 KiB.")
    }
    buffer.write_bytes(chunk)
  }
  @json.parse(@utf8.decode(buffer.to_bytes())) catch {
    _ => raise PublicError(400, "invalid_json", "Invalid JSON body.")
  }
}
