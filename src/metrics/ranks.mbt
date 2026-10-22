///|
/// Read one opened resource into a bounded snapshot. The extra byte detects
/// oversized resources without trusting a separate stat/path lookup. Hashing
/// and parsing use these same bytes; short/oversized files fail the digest.
async fn read_resource(path : String, canonical_size : Int32) -> Bytes {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let buffer = FixedArray::make(canonical_size + 1, b'\x00')
  let mut received = 0
  while received < buffer.length() {
    let n = file.read(
      buffer,
      offset=received,
      max_len=@cmp.minimum(1024 * 1024, buffer.length() - received),
    )
    if n == 0 {
      break
    }
    received += n
  }
  buffer.unsafe_reinterpret_as_bytes()[:received].to_owned()
}

///|
fn rank_base64_value(byte : Byte) -> Int32 {
  match byte {
    b'A'..<=b'Z' => byte.to_int() - 65
    b'a'..<=b'z' => byte.to_int() - 97 + 26
    b'0'..<=b'9' => byte.to_int() - 48 + 52
    b'+' => 62
    b'/' => 63
    _ => -1
  }
}

///|
/// Decode directly to the immutable map key, with no UTF-16 field or scratch
/// buffer. Validate alphabet, padding placement and unused low bits, including
/// the unpadded form accepted by core Base64.
fn read_rank_token(field : BytesView) -> Bytes raise {
  let mut end = field.length()
  let mut padding = 0
  while end > 0 && field[end - 1] == b'=' {
    end -= 1
    padding += 1
  }
  let tail = end % 4
  if tail == 1 ||
    padding > 2 ||
    (padding > 0 && (field.length() % 4 != 0 || tail + padding != 4)) {
    raise ResourceError("invalid o200k Base64 token")
  }
  let decoded = FixedArray::make(end / 4 * 3 + tail * 6 / 8, b'\x00')
  let mut input = 0
  let mut output = 0
  while input + 4 <= end {
    let a = rank_base64_value(field[input])
    let b = rank_base64_value(field[input + 1])
    let c = rank_base64_value(field[input + 2])
    let d = rank_base64_value(field[input + 3])
    if (a | b | c | d) < 0 {
      raise ResourceError("invalid o200k Base64 token")
    }
    decoded[output] = ((a << 2) | (b >> 4)).to_byte()
    decoded[output + 1] = ((b << 4) | (c >> 2)).to_byte()
    decoded[output + 2] = ((c << 6) | d).to_byte()
    input += 4
    output += 3
  }
  if tail >= 2 {
    let a = rank_base64_value(field[input])
    let b = rank_base64_value(field[input + 1])
    if (a | b) < 0 || (tail == 2 && (b & 15) != 0) {
      raise ResourceError("invalid o200k Base64 token")
    }
    decoded[output] = ((a << 2) | (b >> 4)).to_byte()
    if tail == 3 {
      let c = rank_base64_value(field[input + 2])
      if c < 0 || (c & 3) != 0 {
        raise ResourceError("invalid o200k Base64 token")
      }
      decoded[output + 1] = ((b << 4) | (c >> 2)).to_byte()
    }
  }
  // No mutable alias escapes or is used after this conversion.
  decoded.unsafe_reinterpret_as_bytes()
}

///|
fn read_ranks(bytes : Bytes) -> Map[Bytes, Int32] raise {
  let ranks : Map[Bytes, Int32] = Map([], capacity=199998)
  let mut pos = 0
  while pos < bytes.length() {
    if bytes[pos] == b'\n' {
      pos += 1
      continue
    }
    let start = pos
    while pos < bytes.length() && bytes[pos] != b' ' && bytes[pos] != b'\n' {
      pos += 1
    }
    if pos == bytes.length() || bytes[pos] != b' ' {
      raise ResourceError("invalid o200k ranks record")
    }
    let token = read_rank_token(bytes[start:pos])
    pos += 1
    let rank_start = pos
    let mut rank = 0
    while pos < bytes.length() && bytes[pos] != b'\n' {
      let digit = bytes[pos].to_int() - 48
      if digit < 0 || digit > 9 || rank > (2147483647 - digit) / 10 {
        raise ResourceError("invalid o200k decimal rank")
      }
      rank = rank * 10 + digit
      pos += 1
    }
    if pos == rank_start {
      raise ResourceError("invalid o200k decimal rank")
    }
    let previous_size = ranks.length()
    if rank != previous_size {
      raise ResourceError("invalid o200k rank sequence")
    }
    ranks[token] = rank
    // Insertion hashes once; an overwritten key leaves the length unchanged.
    if ranks.length() != previous_size + 1 {
      raise ResourceError("invalid o200k rank sequence")
    }
  }
  if ranks.length() != 199998 {
    raise ResourceError("incomplete o200k ranks")
  }
  for b in 0..<256 {
    if !ranks.contains(Bytes::make(1, b.to_byte())) {
      raise ResourceError("missing o200k byte token")
    }
  }
  ranks
}
