///|
priv enum Atom {
  Literal(Char)
  Any
  Star
  Class(Bool, Array[(Char, Char)])
}

///|
priv enum Segment {
  Recursive
  Exact(String)
  Component(Array[Atom])
}

///|
priv struct Pattern {
  segments : Array[Segment]
  basename : Bool
  directory : Bool
  bytewise : Bool
}

///|
fn invalid_pattern(
  source : String,
  line : Int32,
  pattern : String,
  detail : String,
) -> SelectionError {
  InvalidPattern(source~, line~, pattern~, detail~)
}

///|
fn compile_pattern(
  raw : String,
  source : String,
  line : Int32,
  custom : Bool,
) -> Pattern raise SelectionError {
  let bad = (detail : String) => invalid_pattern(source, line, raw, detail)
  if raw == "" {
    raise bad("empty pattern")
  }
  if custom &&
    (
      raw.has_prefix("/") ||
      raw.has_prefix("\\") ||
      raw.has_prefix("!") ||
      raw.contains(":")
    ) {
    raise bad("absolute paths and negation are not supported")
  }
  let anchored = raw.has_prefix("/")
  let directory = raw.has_suffix("/")
  let start = if anchored { 1 } else { 0 }
  let end = raw.length() - (if directory { 1 } else { 0 })
  if end <= start {
    raise bad("empty pattern")
  }
  let text = raw[start:end].to_owned()
  let segments : Array[Segment] = []
  for part in text.split("/") {
    if part == "" || part == "." || part == ".." {
      raise bad("empty, '.' or '..' component")
    }
    if part == "**" {
      segments.push(Recursive)
      continue
    }
    if custom && part.contains("**") {
      raise bad("'**' must occupy a whole component")
    }
    let chars = part.to_owned().to_array()
    let atoms : Array[Atom] = []
    let mut i = 0
    while i < chars.length() {
      match chars[i] {
        '\\' => {
          i += 1
          if i == chars.length() {
            raise bad("dangling escape")
          }
          push_literal(atoms, chars[i], custom)
        }
        '*' => if atoms.last() is Some(Star) { () } else { atoms.push(Star) }
        '?' => atoms.push(Any)
        '[' => {
          i += 1
          let negative = i < chars.length() &&
            (chars[i] == '!' || chars[i] == '^')
          if negative {
            i += 1
          }
          let ranges : Array[(Char, Char)] = []
          // A leading ']' is a literal class member, as in Git wildmatch.
          if i < chars.length() && chars[i] == ']' {
            ranges.push((']', ']'))
            i += 1
          }
          while i < chars.length() && chars[i] != ']' {
            let mut lo = chars[i]
            if lo == '\\' {
              i += 1
              if i == chars.length() {
                raise bad("dangling class escape")
              }
              lo = chars[i]
            }
            i += 1
            let mut hi = lo
            if i + 1 < chars.length() && chars[i] == '-' && chars[i + 1] != ']' {
              i += 1
              if chars[i] == '\\' {
                i += 1
              }
              if i == chars.length() {
                raise bad("dangling range escape")
              }
              hi = chars[i]
              i += 1
              if hi < lo {
                raise bad("reversed character range")
              }
            }
            if !custom && (lo.to_int() >= 128 || hi.to_int() >= 128) {
              raise bad("non-ASCII Git character classes are unsupported")
            }
            ranges.push((lo, hi))
          }
          if i == chars.length() || ranges.is_empty() {
            raise bad("unclosed or empty character class")
          }
          atoms.push(Class(negative, ranges))
        }
        ']' =>
          if custom {
            raise bad("unmatched ']'")
          } else {
            atoms.push(Literal(']'))
          }
        c => push_literal(atoms, c, custom)
      }
      i += 1
    }
    if atoms.all(atom => atom is Literal(_)) {
      // Recover the unescaped spelling, not the Git bytewise atom encoding.
      // Literal equality is identical in Unicode and UTF-8 byte modes.
      let literal = StringBuilder()
      let mut index = 0
      while index < chars.length() {
        if chars[index] == '\\' {
          index += 1
        }
        literal.write_char(chars[index])
        index += 1
      }
      segments.push(Exact(literal.to_string()))
    } else {
      segments.push(Component(atoms))
    }
  }
  {
    segments,
    basename: !anchored && !text.contains("/"),
    directory,
    bytewise: !custom,
  }
}

///|
fn push_literal(atoms : Array[Atom], char : Char, custom : Bool) -> Unit {
  if custom {
    atoms.push(Literal(char))
  } else {
    for byte in @utf8.encode(char.to_string()) {
      atoms.push(Literal(byte.to_int().unsafe_to_char()))
    }
  }
}

///|
fn component_matches(
  atoms : Array[Atom],
  text : String,
  bytewise : Bool,
) -> Bool {
  let chars = if bytewise {
    @utf8.encode(text).to_array().map(b => b.to_int().unsafe_to_char())
  } else {
    text.to_array()
  }
  let mut previous = Array::make(chars.length() + 1, false)
  let mut next = Array::make(chars.length() + 1, false)
  previous[0] = true
  for atom in atoms {
    next.fill(false)
    match atom {
      Star => {
        next[0] = previous[0]
        for i in 0..<chars.length() {
          next[i + 1] = previous[i + 1] || next[i]
        }
      }
      _ =>
        for i in 0..<chars.length() {
          let matches = match atom {
            Literal(c) => c == chars[i]
            Any => true
            Class(negative, ranges) =>
              ranges.any(r => r.0 <= chars[i] && chars[i] <= r.1) != negative
            Star => false
          }
          next[i + 1] = previous[i] && matches
        }
    }
    let row = previous
    previous = next
    next = row
  }
  previous[chars.length()]
}

///|
fn Pattern::matches_parts(
  self : Pattern,
  parts : ArrayView[String],
  is_dir : Bool,
) -> Bool {
  if self.directory && !is_dir {
    return false
  }
  if self.basename {
    return match self.segments[0] {
      Recursive => true
      Exact(text) => text == parts[parts.length() - 1]
      Component(atoms) =>
        component_matches(atoms, parts[parts.length() - 1], self.bytewise)
    }
  }
  let mut previous = Array::make(parts.length() + 1, false)
  previous[0] = true
  for index, segment in self.segments {
    let next = Array::make(parts.length() + 1, false)
    match segment {
      Recursive => {
        // A trailing '/**' consumes at least one path component.
        let trailing = index == self.segments.length() - 1 && index > 0
        next[0] = previous[0] && !trailing
        for i in 0..<parts.length() {
          next[i + 1] = next[i] ||
            (if trailing { previous[i] } else { previous[i + 1] })
        }
      }
      Exact(text) =>
        for i in 0..<parts.length() {
          next[i + 1] = previous[i] && text == parts[i]
        }
      Component(atoms) =>
        for i in 0..<parts.length() {
          next[i + 1] = previous[i] &&
            component_matches(atoms, parts[i], self.bytewise)
        }
    }
    previous = next
  }
  previous[parts.length()]
}

///|
fn included_parts(patterns : Array[Pattern], parts : ArrayView[String]) -> Bool {
  if patterns.is_empty() {
    return true
  }
  if patterns.any(p => p.matches_parts(parts, false)) {
    return true
  }
  for i in 1..<parts.length() {
    if patterns.any(p => p.matches_parts(parts[:i], true)) {
      return true
    }
  }
  false
}
