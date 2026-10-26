///|
// Ordered alternatives of tiktoken 0.14.0's o200k_base regex. All positions
// are UTF-8 byte boundaries in the snapshot produced by @utf8.encode, not
// scalar/UTF-16 indices. Keep the whole Bytes snapshot here: a view would add
// per-piece view construction and per-scalar offset arithmetic. Only BPE
// needs borrowed piece views. Expand the ASCII read at each scan site: even a
// #inline wrapper can remain a call in native output. Unicode decoding stays
// in one shared slow path, entered only for a non-ASCII leading byte.
fn Encoder::piece_end(self : Encoder, bytes : Bytes, start : Int32) -> Int32 {
  let n = bytes.length()
  let leading = bytes[start].to_int()
  let first = if leading < 0x80 {
    leading
  } else {
    multibyte_scalar_at(bytes, start, leading)
  }
  let after_first = start + scalar_width(first)
  let category = self.category(first)
  let prefix = first != '\r' && first != '\n' && (category & 12) == 0
  for branch in 0..<2 {
    // The optional prefix is greedy, but may need to backtrack (e.g. one mark).
    if prefix {
      if self.letter_end(bytes, after_first, branch) is Some(end) {
        return contraction_end(bytes, end)
      }
    }
    if self.letter_end(bytes, start, branch) is Some(end) {
      return contraction_end(bytes, end)
    }
  }
  if (category & 8) != 0 {
    let mut end = after_first
    // The bound counts Unicode N scalars, not bytes or just ASCII digits.
    for _ in 0..<2 {
      if end == n {
        break
      }
      let leading = bytes[end].to_int()
      let cp = if leading < 0x80 {
        leading
      } else {
        multibyte_scalar_at(bytes, end, leading)
      }
      if (self.category(cp) & 8) == 0 {
        break
      }
      end += scalar_width(cp)
    }
    return end
  }
  let punctuation_start = if first == ' ' { after_first } else { start }
  let mut end = punctuation_start
  while end < n {
    let leading = bytes[end].to_int()
    let cp = if leading < 0x80 {
      leading
    } else {
      multibyte_scalar_at(bytes, end, leading)
    }
    if is_space(cp) || (self.category(cp) & 12) != 0 {
      break
    }
    end += scalar_width(cp)
  }
  if end > punctuation_start {
    while end < n && bytes[end] is (b'\r' | b'\n' | b'/') {
      end += 1
    }
    return end
  }
  // \s*[\r\n]+: backtrack the greedy whitespace run to its last CR/LF.
  let mut last_newline = start
  let mut last_space = start
  end = start
  while end < n {
    let leading = bytes[end].to_int()
    let cp = if leading < 0x80 {
      leading
    } else {
      multibyte_scalar_at(bytes, end, leading)
    }
    if !is_space(cp) {
      break
    }
    last_space = end
    end += scalar_width(cp)
    if cp == '\r' || cp == '\n' {
      last_newline = end
    }
  }
  if last_newline > start {
    return last_newline
  }
  // \s+(?!\S): leave one whole whitespace scalar at a non-space boundary.
  if end == n {
    return end
  }
  if last_space > start {
    return last_space
  }
  // The final \s+ consumes the remaining single whitespace character.
  end
}

///|
fn Encoder::letter_end(
  self : Encoder,
  bytes : Bytes,
  start : Int32,
  branch : Int32,
) -> Int32? {
  let mut end = start
  let mut last_lower_end = -1
  while end < bytes.length() {
    let leading = bytes[end].to_int()
    let cp = if leading < 0x80 {
      leading
    } else {
      multibyte_scalar_at(bytes, end, leading)
    }
    let category = self.category(cp)
    if (category & 1) == 0 {
      break
    }
    end += scalar_width(cp)
    if (category & 2) != 0 {
      last_lower_end = end
    }
  }
  if branch == 1 && end == start {
    return None
  }
  let lower_start = end
  while end < bytes.length() {
    let leading = bytes[end].to_int()
    let cp = if leading < 0x80 {
      leading
    } else {
      multibyte_scalar_at(bytes, end, leading)
    }
    if (self.category(cp) & 2) == 0 {
      break
    }
    end += scalar_width(cp)
  }
  if branch == 1 || end > lower_start {
    Some(end)
  } else if last_lower_end > start {
    // U* D+ backtracks U* until D+ can consume an overlapping category.
    Some(last_lower_end)
  } else {
    None
  }
}

///|
fn contraction_end(bytes : Bytes, end : Int32) -> Int32 {
  if end + 1 >= bytes.length() || bytes[end] != b'\'' {
    return end
  }
  let cp = scalar_at(bytes, end + 1)
  match cp {
    's' | 'S' | 'ſ' | 't' | 'T' | 'm' | 'M' | 'd' | 'D' =>
      end + 1 + scalar_width(cp)
    'r' | 'R' | 'v' | 'V' =>
      if end + 2 < bytes.length() && bytes[end + 2] is (b'e' | b'E') {
        end + 3
      } else {
        end
      }
    'l' | 'L' =>
      if end + 2 < bytes.length() && bytes[end + 2] is (b'l' | b'L') {
        end + 3
      } else {
        end
      }
    _ => end
  }
}

///|
// Private decoder: input is always the valid UTF-8 snapshot from @utf8.encode,
// and pos is a scalar boundary strictly before its end. Do not use this to
// validate arbitrary input bytes. Native UTF-8 encoding still rejects malformed
// UTF-16 (including strings constructed using unsafe_substring).
#inline
fn scalar_at(bytes : Bytes, pos : Int32) -> Int32 {
  let first = bytes[pos].to_int()
  if first < 0x80 {
    first
  } else {
    multibyte_scalar_at(bytes, pos, first)
  }
}

///|
// The scanner has already read a non-ASCII leading byte at a valid scalar
// boundary. Keep multibyte decoding shared rather than duplicating regex logic.
fn multibyte_scalar_at(bytes : Bytes, pos : Int32, first : Int32) -> Int32 {
  if first < 0xE0 {
    ((first & 0x1F) << 6) | (bytes[pos + 1].to_int() & 0x3F)
  } else if first < 0xF0 {
    ((first & 0x0F) << 12) |
    ((bytes[pos + 1].to_int() & 0x3F) << 6) |
    (bytes[pos + 2].to_int() & 0x3F)
  } else {
    ((first & 0x07) << 18) |
    ((bytes[pos + 1].to_int() & 0x3F) << 12) |
    ((bytes[pos + 2].to_int() & 0x3F) << 6) |
    (bytes[pos + 3].to_int() & 0x3F)
  }
}

///|
#inline
fn scalar_width(cp : Int32) -> Int32 {
  if cp < 0x80 {
    1
  } else if cp < 0x800 {
    2
  } else if cp < 0x10000 {
    3
  } else {
    4
  }
}
