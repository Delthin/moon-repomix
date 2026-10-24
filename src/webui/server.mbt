///|
priv struct State {
  options : @repomix.Options
  runtime : @repomix.Runtime
  resource : String
  port : Int32
  mut busy : Bool
}

///|
let response_headers : Map[String, String] = {
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "cross-origin-resource-policy": "same-origin",
  "content-security-policy": "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
  "connection": "close",
}

///|
async fn respond(
  conn : @http.ServerConnection,
  code : Int32,
  text : String,
  mime : String,
) -> Unit {
  let headers = response_headers.copy()
  headers["content-type"] = mime
  conn.send_response(
    code,
    if code == 200 {
      "OK"
    } else {
      "Request Failed"
    },
    extra_headers=headers,
  )
  conn.write_string(text)
  conn.end_response()
  conn.close()
}

///|
fn session(state : State) -> Json {
  {
    "version": @repomix.version(),
    "workspaceName": @platform.basename(state.options.directory),
    "limits": {
      "maxFiles": state.options.max_files,
      "maxTotalBytes": state.options.max_total_size,
      "maxOutputBytes": 16777216,
    },
    "port": state.port,
  }
}

///|
async fn handle(
  state : State,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let (code, text, mime) = try {
    authorize(request, state.port)
    match (request.meth, request.path) {
      (Get, "/api/session") =>
        (200, session(state).stringify(), "application/json; charset=utf-8")
      (Post, "/api/directories") => {
        let value = @async.with_timeout(
          10000,
          () => read_json(body),
          error=PublicError(400, "body_timeout", "Request body timed out."),
        )
        (
          200,
          directories(state, value).stringify(),
          "application/json; charset=utf-8",
        )
      }
      (Post, "/api/pack") => {
        let value = @async.with_timeout(
          10000,
          () => read_json(body),
          error=PublicError(400, "body_timeout", "Request body timed out."),
        )
        (
          200,
          build(state, pack_request(value)).stringify(),
          "application/json; charset=utf-8",
        )
      }
      (Get, "/" | "/index.html") =>
        (
          200,
          static_text(state.resource, "index.html"),
          "text/html; charset=utf-8",
        )
      (Get, "/app.css") =>
        (200, static_text(state.resource, "app.css"), "text/css; charset=utf-8")
      (Get, "/app.js") =>
        (
          200,
          static_text(state.resource, "app.js"),
          "text/javascript; charset=utf-8",
        )
      _ =>
        raise PublicError(
          400, "unsupported_route", "Unsupported route or method.",
        )
    }
  } catch {
    PublicError(code, stable, message) => {
      let error : Json = { "error": { "code": stable, "message": message } }
      (code, error.stringify(), "application/json; charset=utf-8")
    }
    @repomix.PackError::InputLimitExceeded(..) => {
      let error : Json = {
        "error": {
          "code": "input_limit_exceeded",
          "message": "Workspace input exceeds the host resource limits.",
        },
      }
      (413, error.stringify(), "application/json; charset=utf-8")
    }
    err => {
      if @async.is_cancellation_error(err) {
        raise err
      }
      // No raw filesystem paths, scanner findings or source text cross this boundary.
      let error : Json = {
        "error": {
          "code": "operation_failed",
          "message": "The requested operation could not be completed safely.",
        },
      }
      (422, error.stringify(), "application/json; charset=utf-8")
    }
  }
  respond(conn, code, text, mime)
}

///|
/// Read-only, loopback-only Web UI. Only input resource ceilings from host_options
/// are inherited; callers must reject incompatible host business options.
pub async fn serve(
  host_options : @repomix.Options,
  runtime : @repomix.Runtime,
  resource : String,
  port~ : Int32 = 8765,
) -> Unit {
  if port < 1 || port > 65535 {
    raise PublicError(400, "invalid_port", "Port must be between 1 and 65535.")
  }
  let root = canonical_root(host_options.directory)
  let options = @repomix.options(
    root,
    style=Json,
    max_files=if host_options.max_files < 2000 {
      host_options.max_files
    } else {
      2000
    },
    max_total_size=if host_options.max_total_size < 16777216L {
      host_options.max_total_size
    } else {
      16777216L
    },
  )
  let options = {
    ..options,
    max_file_size: if host_options.max_file_size < 2097152 {
      host_options.max_file_size
    } else {
      2097152
    },
  }
  let state : State = { options, runtime, resource, port, busy: false, }
  let server = @http.Server(
    @socket.Addr::parse("127.0.0.1:" + port.to_string()),
  )
  defer server.close()
  @stdio.stdout.write(
    "Web UI: http://127.0.0.1:" +
    port.to_string() +
    "\nAuthorized workspace: " +
    @platform.basename(root) +
    " (read-only local access)\n",
  )
  server.run_forever(
    (request, body, conn) => handle(state, request, body, conn),
    max_connections=16,
  )
}
