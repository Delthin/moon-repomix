///|
/// Server identity and only the capabilities implemented by the application.
pub(all) struct Info {
  name : String
  version : String
  capabilities : Json
  instructions : String
}

///|
/// Positive host limits. Values above the defaults are rejected.
pub(all) struct Limits {
  max_line_bytes : Int32
  max_in_flight : Int32
  timeout_ms : Int32
}

///|
pub fn Limits::default() -> Limits {
  { max_line_bytes: 1048576, max_in_flight: 4, timeout_ms: 60000, }
}

///|
/// Only explicitly safe application errors may cross the protocol boundary.
/// Do not put input values, paths, exception text or source locations here.
pub(all) suberror RpcError {
  Protocol(code~ : Int32, message~ : String, data~ : Json)
}

///|
let version_key : String = "io.modelcontextprotocol/protocolVersion"

///|
let client_key : String = "io.modelcontextprotocol/clientCapabilities"

///|
fn supported_versions() -> Json {
  ["2026-07-28", "2025-11-25", "2025-06-18"]
}

///|
fn supported_modern(version : String) -> Bool {
  version == "2026-07-28"
}

///|
fn rpc_error(id : Json, code : Int32, message : String, data? : Json) -> Json {
  let error : Map[String, Json] = {
    "code": Json(code),
    "message": Json(message),
  }
  if data is Some(data) {
    error["data"] = data
  }
  { "jsonrpc": "2.0", "id": id, "error": Json::object(error) }
}

///|
fn success(id : Json, result : Json, modern : Bool) -> Json {
  let result = if modern && result is Object(fields) {
    let copy = fields.copy()
    copy["resultType"] = "complete"
    Json::object(copy)
  } else {
    result
  }
  { "jsonrpc": "2.0", "id": id, "result": result }
}

///|
fn safe_id(id : Json) -> Bool {
  match id {
    String(_) => true
    Number(n, ..) =>
      n >= -9007199254740991.0 && n <= 9007199254740991.0 && n.floor() == n
    _ => false
  }
}

///|
// JSON number spellings (1, 1.0, 1e0) identify the same request. Preserve
// string/number separation, but never use an untrusted numeric repr as a key.
fn id_key(id : Json) -> String {
  match id {
    Number(n, ..) => if n == 0 { "0" } else { Json::number(n).stringify() }
    _ => id.stringify()
  }
}

///|
priv struct Session {
  mut initializing : Bool
  mut ready : Bool
}

///|
priv enum Action {
  Ignore
  Reply(Json)
  Cancel(Json)
  Call(id~ : Json, name~ : String, params~ : Json, modern~ : Bool)
}
