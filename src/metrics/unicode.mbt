///|
// Bit 0: Lu/Lt/Lm/Lo/M; bit 1: Ll/Lm/Lo/M; bit 2: L; bit 3: N.
// Categories are Unicode 16.0.0, matching regex 1.13.1 used by tiktoken 0.14.0.
fn read_categories(source : String) -> FixedArray[Byte] raise {
  let categories = FixedArray::make(0x110000, b'\x00')
  for line in source.split("\n") {
    let record = line.split("#").collect()[0].trim()
    if record.is_empty() {
      continue
    }
    let fields = record.split(";").collect()
    guard fields.length() == 2 else {
      raise ResourceError("invalid Unicode category record")
    }
    let mask : Byte = match fields[1].trim() {
      "Lu" | "Lt" => 5
      "Ll" => 6
      "Lm" | "Lo" => 7
      "Mn" | "Mc" | "Me" => 3
      "Nd" | "Nl" | "No" => 8
      _ => 0
    }
    if mask == 0 {
      continue
    }
    let range = fields[0].trim().split("..").collect()
    let first = @string.parse_int(range[0], base=16)
    let last = @string.parse_int(range[range.length() - 1], base=16)
    if first < 0 || first > last || last >= categories.length() {
      raise ResourceError("invalid Unicode category range")
    }
    for cp in first..<=last {
      categories[cp] = mask
    }
  }
  categories
}

///|
fn Encoder::category(self : Encoder, c : Char) -> Int32 {
  self.categories[c.to_int()].to_int()
}

///|
// Unicode White_Space, not the host language's whitespace approximation.
fn is_space(c : Char) -> Bool {
  match c.to_int() {
    0x09..<=0x0D
    | 0x20
    | 0x85
    | 0xA0
    | 0x1680
    | 0x2000..<=0x200A
    | 0x2028
    | 0x2029
    | 0x202F
    | 0x205F
    | 0x3000 => true
    _ => false
  }
}
