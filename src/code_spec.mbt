///|
/// A malformed code-reading request, rejected before filesystem access.
pub(all) suberror CodeContextError {
  InvalidCodeSpec
}

///|
/// Immutable validated request for `read_code_context`.
pub struct CodeContextSpec {
  max_tokens : Int32
  priv source : String
}

///|
priv struct CodeRequest {
  path : String
  symbols : Array[String]
  ranges : Array[@compression.LineRange]
  full : Bool
  outline : Bool
  dependencies : Bool
}

///|
priv struct CodeDescription {
  max_tokens : Int32
  max_read_bytes : Int64
  requests : Array[CodeRequest]
}

///|
fn code_bool(
  fields : Map[String, Json],
  key : String,
) -> Bool raise TaskContextError {
  match fields.get(key) {
    None | Some(False) => false
    Some(True) => true
    _ => raise InvalidTaskSpec
  }
}

///|
fn parse_code_description(
  value : Json,
) -> CodeDescription raise TaskContextError {
  let fields = task_fields(value, ["maxTokens", "maxReadBytes", "requests"])
  let max_tokens = task_integer(
    fields.get("maxTokens").unwrap_or(Json::null()),
    1,
    2147483647,
  )
  let max_read_bytes = task_integer(
    fields.get("maxReadBytes").unwrap_or(Json(16777216)),
    1,
    16777216,
  ).to_int64()
  guard fields.get("requests") is Some(Array(values)) &&
    !values.is_empty() &&
    values.length() <= 32 else {
    raise InvalidTaskSpec
  }
  let paths : Set[String] = Set([])
  let requests : Array[CodeRequest] = []
  for value in values {
    let entry = task_fields(value, [
      "path", "symbols", "ranges", "full", "outline", "includeDependencies",
    ])
    guard entry.get("path") is Some(String(path)) &&
      task_path(path) &&
      !paths.contains(path) else {
      raise InvalidTaskSpec
    }
    paths.add(path)
    let full = code_bool(entry, "full")
    let outline = code_bool(entry, "outline")
    let dependencies = code_bool(entry, "includeDependencies")
    let symbols : Array[String] = []
    if entry.get("symbols") is Some(value) {
      guard value is Array(items) && !items.is_empty() && items.length() <= 16 else {
        raise InvalidTaskSpec
      }
      for item in items {
        guard item is String(name) &&
          !name.is_empty() &&
          @utf8.encode(name).length() <= 256 &&
          !name.contains("\u0000") &&
          !name.contains("\n") &&
          !name.contains("\r") &&
          !symbols.contains(name) else {
          raise InvalidTaskSpec
        }
        symbols.push(name)
      }
    }
    let ranges : Array[@compression.LineRange] = []
    if entry.get("ranges") is Some(value) {
      guard value is Array(items) && !items.is_empty() && items.length() <= 16 else {
        raise InvalidTaskSpec
      }
      for item in items {
        let pair = task_fields(item, ["startLine", "endLine"])
        let start_line = task_integer(
          pair.get("startLine").unwrap_or(Json::null()),
          1,
          2147483647,
        )
        let end_line = task_integer(
          pair.get("endLine").unwrap_or(Json::null()),
          start_line,
          2147483647,
        )
        ranges.push({ start_line, end_line, })
      }
    }
    let selectors = (if entry.contains("full") { 1 } else { 0 }) +
      (if entry.contains("outline") { 1 } else { 0 }) +
      (if symbols.is_empty() { 0 } else { 1 }) +
      (if ranges.is_empty() { 0 } else { 1 })
    if selectors != 1 ||
      (entry.contains("full") && !full) ||
      (entry.contains("outline") && !outline) ||
      (dependencies && symbols.is_empty()) {
      raise InvalidTaskSpec
    }
    requests.push({ path, symbols, ranges, full, outline, dependencies, })
  }
  { max_tokens, max_read_bytes, requests, }
}

///|
/// Each path selects exactly one of `symbols`, inclusive `ranges`, `full:true`,
/// or `outline:true`. `includeDependencies` is available only with symbols.
/// Unknown fields, duplicate paths, and non-canonical relative paths fail.
///
/// ```mbt check
/// test "code context request example" {
///   let spec = @moon_repomix.CodeContextSpec::from_json({
///     "maxTokens": 4000,
///     "requests": [{ "path": "lib/response.js", "symbols": ["res.render"] }],
///   })
///   assert_eq(spec.max_tokens, 4000)
/// }
/// ```
pub fn CodeContextSpec::from_json(
  value : Json,
) -> CodeContextSpec raise CodeContextError {
  let source = value.stringify()
  if @utf8.encode(source).length() > 65536 {
    raise InvalidCodeSpec
  }
  let parsed = parse_code_description(value) catch {
    _ => raise InvalidCodeSpec
  }
  { max_tokens: parsed.max_tokens, source, }
}
