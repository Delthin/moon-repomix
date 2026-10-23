///|
priv struct Resource {
  uri : String
  name : String
  mime : String
  text : String
  tokens : Int32
  bytes : Int32
}

///|
priv struct State {
  options : @repomix.Options
  runtime : @repomix.Runtime
  session_prefix : String
  max_tokens : Int32
  max_output_bytes : Int32
  max_volumes : Int32
  resources : Map[String, Resource]
  mut next_run : Int32
  mut busy : Bool
}

///|
fn[T] invalid() -> T raise {
  raise @rpc.Protocol(code=-32602, message="Invalid params", data=Json::null())
}

///|
fn fields(value : Json, allowed : Array[String]) -> Map[String, Json] raise {
  guard value is Object(values) else { return invalid() }
  for key in values.keys() {
    if !allowed.contains(key) {
      return invalid()
    }
  }
  values
}

///|
fn positive(value : Json, maximum : Int32) -> Int32 raise {
  guard value is Number(n, ..) &&
    n >= 1 &&
    n <= maximum.to_double() &&
    n.to_int().to_double() == n else {
    return invalid()
  }
  n.to_int()
}

///|
fn error_result(category : String) -> Json {
  {
    "content": [{ "type": "text", "text": category }],
    "structuredContent": { "ok": false, "error": { "category": category } },
    "isError": true,
  }
}

///|
fn mime(style : @repomix.Style) -> String {
  match style {
    Xml => "application/xml"
    Markdown => "text/markdown"
    Json => "application/json"
    Plain => "text/plain"
  }
}

///|
fn security(value : @repomix.SecurityStatus) -> String {
  match value {
    Passed => "passed"
    Excluded => "excluded"
    Disabled => "disabled"
  }
}

///|
fn resource_description(value : Resource) -> Json {
  {
    "uri": value.uri,
    "name": value.name,
    "mimeType": value.mime,
    "size": value.bytes,
  }
}

///|
fn explanation_paths(args : Json) -> Array[String] raise {
  let values = fields(args, ["paths"])
  guard values.get("paths") is Some(Array(paths)) && paths.length() <= 256 else {
    return invalid()
  }
  let result : Array[String] = []
  for path in paths {
    guard path is String(path) &&
      safe_path(path) &&
      @utf8.encode(path).length() <= 4096 else {
      return invalid()
    }
    result.push(path)
  }
  result
}

///|
fn requested_options(
  base : @repomix.Options,
  maximum : Int32,
  args : Json,
) -> (@repomix.Options, Int32) raise {
  let values = fields(args, ["filePaths", "maxTokens", "compress", "style"])
  let cap = match values.get("maxTokens") {
    None => maximum
    Some(value) => positive(value, maximum)
  }
  let compress = match values.get("compress") {
    None => base.compress
    Some(True) => true
    Some(False) => false
    _ => return invalid()
  }
  let style = match values.get("style") {
    None => base.style
    Some(String("xml")) => @repomix.Style::Xml
    Some(String("markdown")) => @repomix.Style::Markdown
    Some(String("json")) => @repomix.Style::Json
    Some(String("plain")) => @repomix.Style::Plain
    _ => return invalid()
  }
  let file_paths = match values.get("filePaths") {
    None => base.file_paths
    Some(Array(paths)) => {
      if paths.length() > 4096 {
        return invalid()
      }
      let requested : Array[String] = []
      for path in paths {
        guard path is String(path) &&
          safe_path(path) &&
          @utf8.encode(path).length() <= 4096 else {
          return invalid()
        }
        requested.push(path)
      }
      match base.file_paths {
        None => Some(requested)
        Some(host) => {
          let allowed : Set[String] = Set([])
          for path in host {
            allowed.add(path)
          }
          Some(requested.filter(path => allowed.contains(path)))
        }
      }
    }
    _ => return invalid()
  }
  ({ ..base, compress, style, file_paths, }, cap)
}
