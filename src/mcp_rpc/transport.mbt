///|
priv struct Pending {
  mut task : @async.Task[Unit]?
  mut cancelled : Bool
  mut responding : Bool
}

///|
// A frame is committed when the writer lock is acquired. Once committed it
// must finish, even on cancellation, or stdout could contain interleaved JSON.
// A stalled output terminates the transport rather than holding EOF forever.
async fn write_response(
  output : &@io.Writer,
  lock : @async.Mutex,
  response : Json,
  pending? : Pending,
) -> Unit {
  lock.acquire()
  defer lock.release()
  if pending is Some(pending) {
    if pending.cancelled {
      return
    }
    pending.responding = true
  }
  let line = response.stringify() + "\n"
  @async.protect_from_cancel(() => {
    @async.with_timeout(1000, () => output.write(line))
  })
}

///|
async fn invoke(
  id : Json,
  name : String,
  params : Json,
  modern : Bool,
  handler : async (String, Json) -> Json,
  timeout : Int32,
) -> Json {
  try {
    let result = @async.with_timeout(timeout, () => handler(name, params))
    success(id, result, modern, cacheable=cacheable_method(name))
  } catch {
    err if @async.is_being_cancelled() || @async.is_cancellation_error(err) =>
      raise err
    RpcError::Protocol(code~, message~, data~) =>
      rpc_error(id, protocol_error_code(modern, name, code), message, data~)
    @async.TimeoutError => rpc_error(id, -32000, "Request timed out")
    _ => rpc_error(id, -32603, "Internal error")
  }
}

///|
async fn serve_io(
  info : Info,
  input : &@io.Reader,
  output : &@io.Writer,
  handler~ : async (String, Json) -> Json,
  limits~ : Limits,
) -> Unit {
  let defaults = Limits::default()
  guard limits.max_line_bytes > 0 &&
    limits.max_line_bytes <= defaults.max_line_bytes &&
    limits.max_in_flight > 0 &&
    limits.max_in_flight <= defaults.max_in_flight &&
    limits.timeout_ms > 0 &&
    limits.timeout_ms <= defaults.timeout_ms else {
    raise Protocol(
      code=-32602,
      message="Invalid transport limits",
      data=Json::null(),
    )
  }
  let framer : Framer = {
    input,
    limit: limits.max_line_bytes,
    chunk: b"",
    offset: 0,
  }
  let session : Session = { initializing: false, ready: false, }
  let in_flight : Map[String, Pending] = Map([])
  let lock = @async.Mutex()
  @async.with_task_group(group => {
    for ;; {
      let value = match framer.next() {
        End => break
        TooLong => {
          write_response(
            output,
            lock,
            rpc_error(Json::null(), -32600, "Frame too large"),
          )
          continue
        }
        Line(bytes) =>
          match parse_frame(bytes) {
            None => {
              write_response(
                output,
                lock,
                rpc_error(Json::null(), -32700, "Parse error"),
              )
              continue
            }
            Some(value) => value
          }
      }
      // Check before dispatch: even built-ins must not reuse an in-flight ID,
      // and a rejected duplicate must not mutate lifecycle state.
      if value is { "id": id, .. } &&
        safe_id(id) &&
        in_flight.contains(id_key(id)) {
        write_response(
          output,
          lock,
          rpc_error(id, -32600, "Duplicate request ID"),
        )
        continue
      }
      match dispatch(value, info, session) {
        Ignore => ()
        Reply(response) => write_response(output, lock, response)
        Cancel(id) =>
          if in_flight.get(id_key(id)) is Some(pending) {
            pending.cancelled = true
            if !pending.responding && pending.task is Some(task) {
              task.cancel()
            }
          }
        Call(id~, name~, params~, modern~) => {
          if in_flight.length() >= limits.max_in_flight {
            write_response(output, lock, rpc_error(id, -32000, "Server busy"))
            continue
          }
          let key = id_key(id)
          let pending : Pending = {
            task: None,
            cancelled: false,
            responding: false,
          }
          // Insert first: spawn may start the closure before returning.
          in_flight[key] = pending
          let task = group.spawn(no_wait=true, () => {
            defer in_flight.remove(key)
            let response = invoke(
              id,
              name,
              params,
              modern,
              handler,
              limits.timeout_ms,
            )
            write_response(output, lock, response, pending~)
          })
          pending.task = Some(task)
        }
      }
      // A client can fill a read chunk with notifications. Yield even when
      // dispatch itself does no IO so timers/workers are not starved.
      @async.pause()
      // no_wait children are cancelled by structured concurrency on EOF;
      // with_task_group still waits for their cancellation cleanup to finish.
    }
  })
}

///|
/// Serve LF-delimited UTF-8 JSON-RPC on native stdin/stdout until EOF.
/// Application failures other than Protocol are replaced with a fixed error.
/// Transport failures propagate as a fixed Protocol; cancellation propagates.
/// Handlers must cooperate with cancellation (async IO or periodic pause).
pub async fn serve(
  info : Info,
  handler~ : async (String, Json) -> Json,
  limits~ : Limits = Limits::default(),
) -> Unit {
  serve_io(info, @stdio.stdin, @stdio.stdout, handler~, limits~) catch {
    err if @async.is_being_cancelled() || @async.is_cancellation_error(err) =>
      raise err
    RpcError::Protocol(..) as err => raise err
    _ =>
      raise Protocol(
        code=-32603,
        message="Transport failure",
        data=Json::null(),
      )
  }
}
