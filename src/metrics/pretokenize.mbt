///|
// Ordered alternatives of tiktoken 0.14.0's o200k_base regex. Offsets here are
// Unicode scalar indices, never UTF-16 indices. No regex/locale approximation.
fn Encoder::piece_end(
  self : Encoder,
  chars : Array[Char],
  start : Int32,
) -> Int32 {
  let n = chars.length()
  let first = chars[start]
  let prefix = first != '\r' &&
    first != '\n' &&
    (self.category(first) & 12) == 0
  for branch in 0..<2 {
    // The optional prefix is greedy, but may need to backtrack (e.g. one mark).
    if prefix {
      if self.letter_end(chars, start + 1, branch) is Some(end) {
        return contraction_end(chars, end)
      }
    }
    if self.letter_end(chars, start, branch) is Some(end) {
      return contraction_end(chars, end)
    }
  }
  if (self.category(first) & 8) != 0 {
    let mut end = start + 1
    while end < n && end < start + 3 && (self.category(chars[end]) & 8) != 0 {
      end += 1
    }
    return end
  }
  let punctuation_start = if first == ' ' { start + 1 } else { start }
  let mut end = punctuation_start
  while end < n &&
        !is_space(chars[end]) &&
        (self.category(chars[end]) & 12) == 0 {
    end += 1
  }
  if end > punctuation_start {
    while end < n &&
          (chars[end] == '\r' || chars[end] == '\n' || chars[end] == '/') {
      end += 1
    }
    return end
  }
  // \s*[\r\n]+: backtrack the greedy whitespace run to its last CR/LF.
  let mut last_newline = start
  end = start
  while end < n && is_space(chars[end]) {
    if chars[end] == '\r' || chars[end] == '\n' {
      last_newline = end + 1
    }
    end += 1
  }
  if last_newline > start {
    return last_newline
  }
  // \s+(?!\S): at a non-whitespace boundary leave one whitespace character.
  if end == n {
    return end
  }
  if end > start + 1 {
    return end - 1
  }
  // The final \s+ consumes the remaining single whitespace character.
  end
}

///|
fn Encoder::letter_end(
  self : Encoder,
  chars : Array[Char],
  start : Int32,
  branch : Int32,
) -> Int32? {
  let mut end = start
  let mut last_lower = -1
  while end < chars.length() && (self.category(chars[end]) & 1) != 0 {
    if (self.category(chars[end]) & 2) != 0 {
      last_lower = end
    }
    end += 1
  }
  if branch == 1 && end == start {
    return None
  }
  let lower_start = end
  while end < chars.length() && (self.category(chars[end]) & 2) != 0 {
    end += 1
  }
  if branch == 1 || end > lower_start {
    Some(end)
  } else if last_lower >= start {
    // U* D+ backtracks U* until D+ can consume an overlapping category.
    Some(last_lower + 1)
  } else {
    None
  }
}

///|
fn contraction_end(chars : Array[Char], end : Int32) -> Int32 {
  if end + 1 >= chars.length() || chars[end] != '\'' {
    return end
  }
  match chars[end + 1] {
    's' | 'S' | 'ſ' | 't' | 'T' | 'm' | 'M' | 'd' | 'D' => end + 2
    'r' | 'R' | 'v' | 'V' =>
      if end + 2 < chars.length() &&
        (chars[end + 2] == 'e' || chars[end + 2] == 'E') {
        end + 3
      } else {
        end
      }
    'l' | 'L' =>
      if end + 2 < chars.length() &&
        (chars[end + 2] == 'l' || chars[end + 2] == 'L') {
        end + 3
      } else {
        end
      }
    _ => end
  }
}
