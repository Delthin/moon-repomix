///|
// No modern request mutates the legacy lifecycle. A legacy session only
// authorizes requests that do not carry either modern metadata field.
fn dispatch(value : Json, info : Info, session : Session) -> Action {
  guard value is Object(fields) else {
    return Reply(rpc_error(Json::null(), -32600, "Invalid request"))
  }
  let id = fields.get("id")
  guard fields.get("jsonrpc") == Some(Json("2.0")) &&
    fields.get("method") is Some(String(name)) &&
    (id is None || (id is Some(id) && safe_id(id))) &&
    (fields.get("params") is None || fields.get("params") is Some(Object(_))) else {
    return Reply(rpc_error(Json::null(), -32600, "Invalid request"))
  }
  let params = fields.get("params").unwrap_or(Json::empty_object())
  if id is None {
    // Notifications never receive responses, including unknown/invalid params.
    if name == "notifications/initialized" && session.initializing {
      session.ready = true
    }
    if name == "notifications/cancelled" &&
      params is { "requestId": target, .. } &&
      safe_id(target) {
      return Cancel(target)
    }
    return Ignore
  }
  let id = id.unwrap()
  if name == "initialize" {
    guard !session.initializing &&
      params
      is {
        "protocolVersion": String(version),
        "capabilities": Object(_),
        "clientInfo": { "name": String(_), "version": String(_), .. },
        ..
      } else {
      return Reply(rpc_error(id, -32602, "Invalid params"))
    }
    // Legacy negotiation falls back to the newest supported legacy protocol.
    let selected = if version == "2025-06-18" { version } else { "2025-11-25" }
    session.initializing = true
    return Reply(
      success(
        id,
        {
          "protocolVersion": Json(selected),
          "capabilities": info.capabilities,
          "serverInfo": {
            "name": Json(info.name),
            "version": Json(info.version),
          },
          "instructions": Json(info.instructions),
        },
        false,
      ),
    )
  }
  let meta = match params {
    { "_meta": meta, .. } => Some(meta)
    _ => None
  }
  let has_modern = match meta {
    Some(Object(fields)) =>
      fields.contains(version_key) || fields.contains(client_key)
    Some(_) => true
    None => false
  }
  // Legacy ping is permitted even before initialize/initialized. It does not
  // establish a session or authorize any application method.
  if name == "ping" && !has_modern {
    return Reply(success(id, Json::empty_object(), false))
  }
  let modern = has_modern || name == "server/discover" || !session.ready
  if modern {
    guard meta is Some(Object(meta)) &&
      meta.get(version_key) is Some(String(version)) &&
      meta.get(client_key) is Some(Object(_)) else {
      return Reply(rpc_error(id, -32602, "Invalid params"))
    }
    if !supported_modern(version) {
      return Reply(
        rpc_error(id, -32022, "Unsupported protocol version", data={
          "supported": ["2026-07-28"],
          "requested": Json(version),
        }),
      )
    }
  }
  match name {
    "server/discover" =>
      Reply(
        success(
          id,
          {
            "supportedVersions": supported_versions(),
            "capabilities": info.capabilities,
            "_meta": {
              "io.modelcontextprotocol/serverInfo": {
                "name": Json(info.name),
                "version": Json(info.version),
              },
            },
            "instructions": Json(info.instructions),
          },
          true,
        ),
      )
    "ping" => Reply(success(id, Json::empty_object(), modern))
    _ => Call(id~, name~, params~, modern~)
  }
}
