///|
pub(all) struct Snapshot {
  text : String
  disk_bytes : Int32
  bom_bytes : Int32
}

///|
pub(all) enum ReadResult {
  Loaded(Snapshot)
  Skipped(String)
}

///|
/// Read at most max_bytes + one sentinel byte. Only regular files are opened.
pub async fn read(path : String, max_bytes : Int32) -> ReadResult {
  if max_bytes <= 0 {
    return Skipped("TooLarge")
  }
  try {
    match @fs.kind(path, follow_symlink=false) {
      @fs.SymLink => return Skipped("SymbolicLink")
      @fs.Regular => ()
      _ => return Skipped("UnsupportedFileType")
    }
    let file = @fs.open(path, mode=@fs.ReadOnly)
    defer file.close()
    if file.kind() != @fs.Regular {
      return Skipped("UnsupportedFileType")
    }
    if file.size() > max_bytes.to_int64() {
      return Skipped("TooLarge")
    }
    let buffer = @buffer.Buffer(size_hint=4096)
    for ;; {
      let remaining = max_bytes - buffer.length()
      let size = if remaining >= 65536 { 65536 } else { remaining + 1 }
      match @io.Reader::read_some(file, max_len=size) {
        None => break
        Some(bytes) => {
          if bytes.length() > remaining {
            return Skipped("TooLarge")
          }
          buffer.write_bytes(bytes)
        }
      }
    }
    let bytes = buffer.to_bytes()
    for byte in bytes {
      if byte == b'\x00' {
        return Skipped("Binary")
      }
    }
    let bom = if bytes is [0xef, 0xbb, 0xbf, ..] { 3 } else { 0 }
    let text = @utf8.decode(bytes[bom:], ignore_bom=false) catch {
      _ => return Skipped("InvalidUtf8")
    }
    Loaded({ text, disk_bytes: bytes.length(), bom_bytes: bom, })
  } catch {
    err => {
      if @async.is_cancellation_error(err) {
        raise err
      }
      Skipped("Unreadable")
    }
  }
}
