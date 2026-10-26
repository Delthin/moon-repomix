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
pub(all) struct MeteredRead {
  result : ReadResult
  read_bytes : Int64
}

///|
pub(all) suberror TotalSizeLimitExceeded

///|
/// Read at most max_bytes + one sentinel byte. Only regular files are opened.
pub async fn read(path : String, max_bytes : Int32) -> ReadResult {
  ordinary_result(read_impl(path, max_bytes, None).result)
}

///|
/// Limit raw reads to remaining_bytes plus one probe byte, before decoding.
/// Count every byte read, including BOMs and bytes from skipped/unreadable files.
/// A stat-based TooLarge skip consumes no bytes. Exhaustion raises immediately.
pub async fn read_metered(
  path : String,
  max_bytes : Int32,
  remaining_bytes : Int64,
) -> MeteredRead {
  if remaining_bytes < 0 {
    raise TotalSizeLimitExceeded
  }
  let read = read_impl(path, max_bytes, Some(remaining_bytes))
  { result: ordinary_result(read.result), read_bytes: read.read_bytes, }
}

///|
/// The metered reader with an unforgeable strict-UTF-8 snapshot. Byte accounting,
/// exclusions and the single excess-byte probe are identical to read_metered.
pub async fn read_validated_metered(
  path : String,
  max_bytes : Int32,
  remaining_bytes : Int64,
) -> ValidatedMeteredRead {
  if remaining_bytes < 0 {
    raise TotalSizeLimitExceeded
  }
  read_impl(path, max_bytes, Some(remaining_bytes))
}

///|
async fn read_impl(
  path : String,
  max_bytes : Int32,
  remaining_bytes : Int64?,
) -> ValidatedMeteredRead {
  let consumed = Ref(0L)
  let result : ValidatedReadResult = if max_bytes <= 0 {
    Skipped("TooLarge")
  } else {
    read_regular(path, max_bytes, remaining_bytes, consumed)
  }
  { result, read_bytes: consumed.val, }
}

///|
async fn read_regular(
  path : String,
  max_bytes : Int32,
  remaining_bytes : Int64?,
  consumed : Ref[Int64],
) -> ValidatedReadResult {
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
    read_bounded(file, max_bytes, remaining_bytes, consumed)
  } catch {
    err => {
      if err is TotalSizeLimitExceeded || @async.is_cancellation_error(err) {
        raise err
      }
      Skipped("Unreadable")
    }
  }
}

///|
async fn read_bounded(
  reader : &@io.Reader,
  max_bytes : Int32,
  remaining_bytes : Int64?,
  consumed : Ref[Int64],
) -> ValidatedReadResult {
  let buffer = @buffer.Buffer(size_hint=4096)
  let chunk = FixedArray::make(65536, b'\x00')
  for ;; {
    let remaining = max_bytes - buffer.length()
    let mut size = if remaining >= 65536 { 65536 } else { remaining + 1 }
    if remaining_bytes is Some(limit) {
      let available = limit - consumed.val
      if available < size.to_int64() {
        size = (available + 1).to_int()
      }
    }
    // read_some can prefetch into a larger internal buffer. read passes the
    // exact max_len through to the OS for a newly opened, unbuffered file.
    let count = reader.read(chunk, max_len=size) catch {
      err => {
        if @async.is_cancellation_error(err) {
          raise err
        }
        // Keep consumption from previous successful chunks on read failure.
        return Skipped("Unreadable")
      }
    }
    if count == 0 {
      break
    }
    consumed.val += count.to_int64()
    if remaining_bytes is Some(limit) && consumed.val > limit {
      raise TotalSizeLimitExceeded
    }
    if count > remaining {
      return Skipped("TooLarge")
    }
    buffer.write_bytes(chunk.unsafe_reinterpret_as_bytes()[:count])
  }
  let bytes = buffer.to_bytes()
  for byte in bytes {
    if byte == b'\x00' {
      return Skipped("Binary")
    }
  }
  let proof = @validated_text.decode(bytes) catch {
    _ => return Skipped("InvalidUtf8")
  }
  Loaded({ proof, })
}
