///|
// Explicit bounded input; never read stdin for an ordinary pack/help/version run.
async fn read_stdin(mode : @config.StdinMode) -> Array[String]? {
  if mode is Off {
    return None
  }
  try {
    let limit = 8388608
    let buffer = @buffer.Buffer(size_hint=4096)
    for ;; {
      let remaining = limit - buffer.length()
      let size = if remaining >= 65536 { 65536 } else { remaining + 1 }
      match @io.Reader::read_some(@stdio.stdin, max_len=size) {
        None => break
        Some(bytes) => {
          if bytes.length() > remaining {
            raise InputList
          }
          buffer.write_bytes(bytes)
        }
      }
    }
    let text = @utf8.decode(buffer.to_bytes(), ignore_bom=false)
    Some(@config.parse_file_list(text, nul=mode is Nul))
  } catch {
    err => {
      if @async.is_cancellation_error(err) {
        raise err
      }
      raise InputList
    }
  }
}
