///|
/// Measure before UTF-8 allocation or conversion to an Int32 byte count.
fn byte_length(text : String) -> Int32 raise PartitionError {
  let mut total = 0L
  let mut i = 0
  while i < text.length() {
    let c = text[i].to_int()
    if c >= 0xd800 && c <= 0xdbff {
      if i == text.length() - 1 || text[i + 1] < 0xdc00 || text[i + 1] > 0xdfff {
        raise InvalidTextEncoding
      }
      total += 4L
      i += 2
    } else {
      if c >= 0xdc00 && c <= 0xdfff {
        raise InvalidTextEncoding
      }
      total += if c < 0x80 { 1L } else if c < 0x800 { 2L } else { 3L }
      i += 1
    }
    if total > 2147483647L {
      raise Overflow("UTF-8 bytes")
    }
  }
  total.to_int()
}

///|
fn checked_count(text : String, count : (String) -> Int32 raise) -> Int32 raise {
  let actual = count(text)
  if actual < 0 {
    raise InvalidCount(actual)
  }
  actual
}

///|
fn add_tokens(total : Int64, tokens : Int32) -> Int64 raise PartitionError {
  if total > 9223372036854775807L - tokens.to_int64() {
    raise Overflow("total tokens")
  }
  total + tokens.to_int64()
}

///|
fn volume_id(number : Int32) -> String {
  let digits = number.to_string()
  "part-" + "0".repeat(Int32::max(0, 4 - digits.length())) + digits
}
