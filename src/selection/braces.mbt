///|
priv struct BraceParser {
  raw : String
  source : String
  chars : Array[Char]
  mut position : Int32
}

///|
fn BraceParser::bad(self : BraceParser, detail : String) -> SelectionError {
  invalid_pattern(self.source, 0, self.raw, detail)
}

///|
// Bound both Cartesian products and accumulated alternatives before allocating.
fn BraceParser::append(
  self : BraceParser,
  prefixes : Array[String],
  suffixes : Array[String],
) -> Array[String] raise SelectionError {
  if prefixes.length() > 256 / suffixes.length() {
    raise self.bad("brace expansion exceeds 256 patterns")
  }
  let result : Array[String] = []
  for prefix in prefixes {
    for suffix in suffixes {
      result.push(prefix + suffix)
    }
  }
  result
}

///|
fn BraceParser::sequence(
  self : BraceParser,
  depth : Int32,
) -> Array[String] raise SelectionError {
  let mut result = [""]
  while self.position < self.chars.length() {
    let c = self.chars[self.position]
    if depth > 0 && (c == ',' || c == '}') {
      break
    }
    self.position += 1
    match c {
      '{' => {
        if depth == 8 {
          raise self.bad("brace nesting exceeds 8 levels")
        }
        let alternatives : Array[String] = []
        let mut commas = 0
        while true {
          let values = self.sequence(depth + 1)
          if values.any(v => v == "") {
            raise self.bad("empty brace alternative")
          }
          if alternatives.length() + values.length() > 256 {
            raise self.bad("brace expansion exceeds 256 patterns")
          }
          alternatives.append(values)
          if self.position == self.chars.length() {
            raise self.bad("unclosed brace")
          }
          let delimiter = self.chars[self.position]
          self.position += 1
          if delimiter == '}' {
            break
          }
          commas += 1
        }
        if commas == 0 {
          raise self.bad("braces require comma-separated alternatives")
        }
        result = self.append(result, alternatives)
      }
      '}' => raise self.bad("unmatched '}'")
      '\\' => {
        if self.position == self.chars.length() {
          raise self.bad("dangling escape")
        }
        let escaped = "\\" + self.chars[self.position].to_string()
        self.position += 1
        result = self.append(result, [escaped])
      }
      '[' => {
        // Leave classes verbatim for the glob compiler, including braces/commas.
        let start = self.position - 1
        if self.position < self.chars.length() &&
          (self.chars[self.position] == '!' || self.chars[self.position] == '^') {
          self.position += 1
        }
        if self.position < self.chars.length() &&
          self.chars[self.position] == ']' {
          self.position += 1
        }
        while self.position < self.chars.length() {
          let item = self.chars[self.position]
          self.position += 1
          if item == '\\' && self.position < self.chars.length() {
            self.position += 1
          } else if item == ']' {
            break
          }
        }
        result = self.append(result, [
          String::from_array(self.chars[start:self.position]),
        ])
      }
      _ => result = self.append(result, [c.to_string()])
    }
  }
  result
}

///|
fn custom_patterns(
  raw_patterns : Array[String],
  source : String,
  root_relative~ : Bool = false,
) -> Array[Pattern] raise SelectionError {
  let result : Array[Pattern] = []
  for raw in raw_patterns {
    let parser : BraceParser = {
      raw,
      source,
      chars: raw.to_array(),
      position: 0,
    }
    let expanded = parser.sequence(0)
    if result.length() + expanded.length() > 256 {
      raise parser.bad("expanded pattern list exceeds 256 patterns")
    }
    for text in expanded {
      let pattern = compile_pattern(text, source, 0, true) catch {
        SelectionError::InvalidPattern(detail~, ..) => raise parser.bad(detail)
        e => raise e
      }
      result.push({
        ..pattern,
        basename: pattern.basename && source != "include" && !root_relative,
      })
    }
  }
  result
}
