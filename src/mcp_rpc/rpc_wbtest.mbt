///|
fn test_info() -> Info {
  {
    name: "test",
    version: "1",
    capabilities: { "tools": {} },
    instructions: "local",
  }
}

///|
fn modern_params(version~ : String = "2026-07-28") -> Json {
  {
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": Json(version),
      "io.modelcontextprotocol/clientCapabilities": {},
    },
  }
}

///|
fn request(id : Json, name : String, params~ : Json = modern_params()) -> Json {
  { "jsonrpc": "2.0", "id": id, "method": Json(name), "params": params }
}

///|
fn reply(action : Action) -> Json raise {
  match action {
    Reply(value) => value
    _ => fail("Expected reply")
  }
}

///|
fn assert_code(action : Action, code : Int32) -> Unit raise {
  assert_true(
    reply(action) is { "error": { "code": value, .. }, .. } &&
    value == Json(code),
  )
}

///|
test "dispatch versions, lifecycle, envelopes and safe IDs" {
  let info = test_info()
  let session : Session = { initializing: false, ready: false, }
  assert_eq(
    reply(
      dispatch({ "jsonrpc": "2.0", "id": -1, "method": "ping" }, info, session),
    ),
    { "jsonrpc": "2.0", "id": -1, "result": {} },
  )
  assert_code(
    dispatch(request(Json(0), "tools/list", params={}), info, session),
    -32602,
  )
  let discover = reply(
    dispatch(request(Json(1), "server/discover"), info, session),
  )
  assert_eq(
    discover,
    success(
      Json(1),
      {
        "resultType": "complete",
        "ttlMs": 0,
        "cacheScope": "private",
        "supportedVersions": ["2026-07-28", "2025-11-25", "2025-06-18"],
        "capabilities": { "tools": {} },
        "_meta": {
          "io.modelcontextprotocol/serverInfo": {
            "name": "test",
            "version": "1",
          },
        },
        "instructions": "local",
      },
      false,
    ),
  )
  assert_code(
    dispatch(request(Json(2), "tools/list", params={}), info, session),
    -32602,
  )
  assert_code(
    dispatch(
      request(Json(2), "ping", params={
        "_meta": { "io.modelcontextprotocol/protocolVersion": "2026-07-28" },
      }),
      info,
      session,
    ),
    -32602,
  )
  let unsupported = reply(
    dispatch(
      request(Json(2), "ping", params={
        "_meta": {
          "io.modelcontextprotocol/protocolVersion": "2099-01-01",
          "io.modelcontextprotocol/clientCapabilities": {},
        },
      }),
      info,
      session,
    ),
  )
  assert_true(
    unsupported
    is {
      "error": {
        "code": -32022,
        "data": { "supported": ["2026-07-28"], "requested": "2099-01-01", .. },
        ..
      },
      ..
    },
  )
  for
    id in [
      Json::null(),
      Json(true),
      Json::empty_object(),
      Json(1.5),
      Json::number(9007199254740992.0),
      Json::number(-9007199254740992.0),
    ] {
    assert_code(dispatch(request(id, "ping"), info, session), -32600)
  }
  for version in ["2025-11-25", "2025-06-18"] {
    assert_eq(
      reply(
        dispatch(
          request(Json(2), "ping", params=modern_params(version~)),
          info,
          session,
        ),
      ),
      {
        "jsonrpc": "2.0",
        "id": 2,
        "error": {
          "code": -32022,
          "message": "Unsupported protocol version",
          "data": { "supported": ["2026-07-28"], "requested": Json(version) },
        },
      },
    )
  }
  assert_true(
    dispatch(request(Json(3), "tools/list"), info, session)
    is Call(modern=true, ..),
  )
  assert_code(
    dispatch(request(Json(4), "tools/list", params={}), info, session),
    -32602,
  )
  assert_true(!session.initializing && !session.ready)
  assert_eq(id_key(@json.parse("-0")), id_key(@json.parse("0")))
  assert_eq(id_key(@json.parse("1e0")), id_key(@json.parse("1.0")))
  for
    id in [
      Json(""),
      Json("string-id"),
      Json(0),
      Json(-1),
      @json.parse("-0"),
      Json::number(9007199254740991.0),
      Json::number(-9007199254740991.0),
    ] {
    assert_true(
      reply(dispatch(request(id, "ping"), info, session))
      is { "result": { "resultType": "complete", .. }, .. },
    )
  }
  assert_code(dispatch(Json::array([]), info, session), -32600)
  assert_code(
    dispatch({ "jsonrpc": "1.0", "id": 1, "method": "ping" }, info, session),
    -32600,
  )
  assert_true(
    dispatch({ "jsonrpc": "2.0", "method": "unknown" }, info, session) is Ignore,
  )
  for version in ["2025-06-18", "2025-11-25", "unknown"] {
    let legacy : Session = { initializing: false, ready: false, }
    let initialized = reply(
      dispatch(
        request(Json(0), "initialize", params={
          "protocolVersion": Json(version),
          "capabilities": {},
          "clientInfo": { "name": "test", "version": "1" },
        }),
        info,
        legacy,
      ),
    )
    let selected = if version == "2025-06-18" { version } else { "2025-11-25" }
    assert_true(
      initialized is { "id": 0, "result": { "protocolVersion": value, .. }, .. } &&
      value == Json(selected),
    )
    assert_eq(
      reply(dispatch(request(Json(-1), "ping", params={}), info, legacy)),
      { "jsonrpc": "2.0", "id": -1, "result": {} },
    )
    assert_code(
      dispatch(request(Json(2), "tools/list", params={}), info, legacy),
      -32602,
    )
    assert_true(
      dispatch(
        { "jsonrpc": "2.0", "method": "notifications/initialized" },
        info,
        legacy,
      )
      is Ignore,
    )
    assert_eq(
      reply(dispatch(request(Json(2), "ping", params={}), info, legacy)),
      { "jsonrpc": "2.0", "id": 2, "result": {} },
    )
    // Modern calls remain independently validated even in a legacy session.
    assert_code(
      dispatch(
        request(Json(3), "ping", params={
          "_meta": { "io.modelcontextprotocol/clientCapabilities": {} },
        }),
        info,
        legacy,
      ),
      -32602,
    )
    assert_code(
      dispatch(
        request(Json(3), "tools/list", params=modern_params(version~)),
        info,
        legacy,
      ),
      -32022,
    )
    assert_true(
      dispatch(request(Json(3), "tools/list"), info, legacy)
      is Call(modern=true, ..),
    )
    assert_true(
      dispatch(request(Json(4), "tools/list", params={}), info, legacy)
      is Call(modern=false, ..),
    )
  }
  for
    name in [
      "server/discover", "tools/list", "resources/list", "resources/read", "resources/templates/list",
      "prompts/list",
    ] {
    assert_true(cacheable_method(name))
    assert_eq(
      success(Json(1), { "x": 2 }, true, cacheable=cacheable_method(name)),
      {
        "jsonrpc": "2.0",
        "id": 1,
        "result": {
          "x": 2,
          "resultType": "complete",
          "ttlMs": 0,
          "cacheScope": "private",
        },
      },
    )
  }
  assert_false(cacheable_method("tools/call"))
  assert_eq(success(Json(1), { "x": 2 }, false, cacheable=true), {
    "jsonrpc": "2.0",
    "id": 1,
    "result": { "x": 2 },
  })
  assert_eq(protocol_error_code(true, "resources/read", -32002), -32602)
  assert_eq(protocol_error_code(false, "resources/read", -32002), -32002)
  assert_eq(protocol_error_code(true, "tools/call", -32002), -32002)
  assert_eq(success(Json(1), { "x": 2 }, true), {
    "jsonrpc": "2.0",
    "id": 1,
    "result": { "x": 2, "resultType": "complete" },
  })
  assert_eq(success(Json(1), Json::array([]), true), {
    "jsonrpc": "2.0",
    "id": 1,
    "result": [],
  })
}

///|
async fn with_server(
  handler : async (String, Json) -> Json,
  body : async (@pipe.PipeWrite, @pipe.PipeRead, @async.Task[Unit]) -> Unit,
  limits~ : Limits = Limits::default(),
) -> Unit {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let (input, client) = @pipe.pipe()
      let (reader, output) = @pipe.pipe()
      defer {
        input.close()
        client.close()
        reader.close()
        output.close()
      }
      let server = group.spawn(no_wait=true, () => {
        defer output.close()
        serve_io(test_info(), input, output, handler~, limits~)
      })
      body(client, reader, server)
    })
  })
}

///|
async fn send(client : @pipe.PipeWrite, value : Json) -> Unit {
  client.write(value.stringify() + "\n")
}

///|
async fn receive(reader : @pipe.PipeRead) -> Json {
  guard reader.read_until("\n") is Some(line) else { fail("Unexpected EOF") }
  @json.parse(line)
}

///|
async test "real pipe bounded framing, UTF8, recovery and unterminated EOF" {
  with_server(
    (_, _) => fail("Unexpected handler"),
    (client, reader, server) => {
      client.write("x".repeat(10000) + "\n")
      assert_true(
        receive(reader)
        is { "error": { "code": -32600, "message": "Frame too large", .. }, .. },
      )
      client.write(b"\xff\n{broken\n[]\n")
      assert_true(receive(reader) is { "error": { "code": -32700, .. }, .. })
      assert_true(receive(reader) is { "error": { "code": -32700, .. }, .. })
      assert_true(receive(reader) is { "error": { "code": -32600, .. }, .. })
      let ping = request(Json("你"), "ping").stringify()
      let bytes = @utf8.encode(ping)
      // Split the UTF8 sequence, not merely JSON token boundaries.
      for i = 0; i < bytes.length(); i = i + 1 {
        client.write(bytes[i:i + 1].to_owned())
      }
      client.write(" ".repeat(256 - bytes.length()) + "\n")
      assert_eq(receive(reader), {
        "jsonrpc": "2.0",
        "id": "你",
        "result": { "resultType": "complete" },
      })
      client.write(request(Json(9), "ping").stringify())
      client.close()
      server.wait()
      assert_eq(reader.read_some(), None)
    },
    limits={ max_line_bytes: 256, max_in_flight: 4, timeout_ms: 60000, },
  )
}

///|
priv suberror UnsafeFailure {
  UnsafeFailure(String)
}

///|
async test "real pipe cancellation, EOF, duplicate, busy, timeout and safe errors" {
  let started = Ref(0)
  let finished = Ref(0)
  with_server(
    (name, _) => {
      if name == "safe" {
        raise Protocol(
          code=-32601,
          message="Method not found",
          data=Json::null(),
        )
      }
      if name == "unsafe" {
        raise UnsafeFailure("SECRET input/source")
      }
      if name == "fast" {
        return { "ok": true }
      }
      started.val += 1
      defer {
        finished.val += 1
      }
      @async.sleep(60000)
      { "unreachable": true }
    },
    (client, reader, server) => {
      send(client, request(Json(1), "slow"))
      send(
        client,
        request(Json::number(1.0, repr="1.0"), "initialize", params={}),
      )
      assert_true(
        receive(reader)
        is {
          "id": 1,
          "error": { "code": -32600, "message": "Duplicate request ID", .. },
          ..
        },
      )
      for id in [2, 3, 4] {
        send(client, request(Json(id), "slow"))
      }
      send(client, request(Json(5), "fast"))
      assert_true(
        receive(reader)
        is { "id": 5, "error": { "message": "Server busy", .. }, .. },
      )
      for id in [1, 2, 3, 4] {
        send(client, {
          "jsonrpc": "2.0",
          "method": "notifications/cancelled",
          "params": {
            "requestId": if id == 1 {
              Json::number(1.0, repr="1e0")
            } else {
              Json(id)
            },
          },
        })
      }
      // Barrier: next request is accepted after cancellation cleanup.
      @async.sleep(5)
      send(client, request(Json(1), "fast"))
      assert_eq(receive(reader), {
        "jsonrpc": "2.0",
        "id": 1,
        "result": { "ok": true, "resultType": "complete" },
      })
      send(client, request(Json(0), "slow"))
      send(client, request(@json.parse("-0"), "ping", params={}))
      assert_true(
        receive(reader)
        is {
          "id": 0,
          "error": { "code": -32600, "message": "Duplicate request ID", .. },
          ..
        },
      )
      send(client, {
        "jsonrpc": "2.0",
        "method": "notifications/cancelled",
        "params": { "requestId": 0 },
      })
      @async.sleep(5)
      send(client, request(Json(-1), "fast"))
      assert_eq(receive(reader), {
        "jsonrpc": "2.0",
        "id": -1,
        "result": { "ok": true, "resultType": "complete" },
      })
      send(client, request(Json(6), "safe"))
      assert_eq(receive(reader), {
        "jsonrpc": "2.0",
        "id": 6,
        "error": { "code": -32601, "message": "Method not found", "data": null },
      })
      send(client, request(Json(7), "unsafe"))
      assert_eq(receive(reader), {
        "jsonrpc": "2.0",
        "id": 7,
        "error": { "code": -32603, "message": "Internal error" },
      })
      send(client, request(Json(8), "slow"))
      assert_eq(receive(reader), {
        "jsonrpc": "2.0",
        "id": 8,
        "error": { "code": -32000, "message": "Request timed out" },
      })
      send(client, request(Json(9), "slow"))
      // Ensure this last task actually entered the handler before closing stdin.
      while started.val < 7 {
        @async.pause()
      }
      client.close()
      server.wait()
      assert_eq(reader.read_some(), None)
      assert_eq(started.val, 7)
      assert_eq(finished.val, 7)
    },
    limits={ max_line_bytes: 1048576, max_in_flight: 4, timeout_ms: 100, },
  )
}

///|
priv struct FragmentedWriter {
  output : @pipe.PipeWrite
  entered : Ref[Bool]
  released : Ref[Bool]
}

///|
impl @io.Writer for FragmentedWriter with fn write_once(
  self,
  bytes,
  offset~,
  len~,
) {
  self.entered.val = true
  while !self.released.val {
    @async.pause()
  }
  @async.pause()
  self.output.write_once(bytes, offset~, len=Int32::min(len, 4096))
}

///|
async test "concurrent real pipe responses stay serial; outbound exceeds input cap" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let (input, client) = @pipe.pipe()
      let (reader, output) = @pipe.pipe()
      defer {
        input.close()
        client.close()
        reader.close()
        output.close()
      }
      let text = "你\\\"".repeat(220000)
      let entered = Ref(false)
      let released = Ref(false)
      let calls = Ref(0)
      let server = group.spawn(no_wait=true, () => {
        defer output.close()
        serve_io(
          test_info(),
          input,
          FragmentedWriter::{ output, entered, released, },
          handler=(_, _) => {
            calls.val += 1
            @async.pause()
            { "text": Json(text) }
          },
          limits=Limits::default(),
        )
      })
      send(client, request(Json(1), "large"))
      while !entered.val {
        @async.pause()
      }
      for id in [2, 3, 4] {
        send(client, request(Json(id), "large"))
      }
      while calls.val < 4 {
        @async.pause()
      }
      send(client, {
        "jsonrpc": "2.0",
        "method": "notifications/cancelled",
        "params": { "requestId": 2 },
      })
      send(client, request(Json(5), "large"))
      // Handler 5 is a barrier proving cancellation was read while stdout was
      // blocked and handler 2 was queued on the writer lock.
      while calls.val < 5 {
        @async.pause()
      }
      released.val = true
      let seen : Set[String] = Set([])
      for i = 0; i < 4; i = i + 1 {
        let result = receive(reader)
        guard result
          is {
            "id": id,
            "result": { "text": value, "resultType": "complete", .. },
            ..
          } else {
          fail("Expected complete large result")
        }
        assert_true(!seen.contains(id.stringify()))
        seen.add(id.stringify())
        assert_eq(value, Json(text))
        assert_true(result.stringify().length() > 1048576)
      }
      assert_eq(seen.length(), 4)
      assert_true(!seen.contains("2"))
      client.close()
      server.wait()
      assert_eq(reader.read_some(), None)
    })
  })
}
