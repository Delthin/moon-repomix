///|
async test "UTF-8 piece boundaries preserve ordered regex alternatives and scalar backtracking" {
  let assets = match @env.get_env_var("TOKENIZER_ASSETS") {
    Some(path) => path
    None => @fs.realpath("assets")
  }
  let encoder : Encoder = {
    ranks: Map([]),
    native: None,
    categories: read_categories(
      @utf8.decode(
        @fs.read_file(assets + "/tokenizer-unicode-16.0.0.txt").binary(),
      ),
    ),
  }
  // Literal partitions follow the ordered o200k regex, independently of the
  // byte scanner. Include non-ASCII boundaries on both sides of backtracking.
  let cases : Array[(String, Array[String])] = [
    (" Aé猫𐐨!", [" Aé猫𐐨", "!"]),
    ("😀Hello", ["😀Hello"]),
    ("猫A", ["猫", "A"]),
    ("\u{0301}A", ["\u{0301}", "A"]),
    ("\u{0301}", ["\u{0301}"]),
    ("!ABCdef", ["!ABCdef"]),
    ("!ABC", ["!ABC"]),
    ("aB", ["a", "B"]),
    ("²Ⅷ𝟛4", ["²Ⅷ𝟛", "4"]),
    ("١２𝟛4", ["١２𝟛", "4"]),
    ("é'ſX", ["é'ſ", "X"]),
    ("a'RE", ["a'RE"]),
    ("a'ré", ["a", "'ré"]),
    ("a'r", ["a", "'r"]),
    ("a'", ["a", "'"]),
    ("A'LLé", ["A'LL", "é"]),
    (" \u{3000}\u{a0}!", [" \u{3000}", "\u{a0}", "!"]),
    (" \u{3000}\u{a0}a", [" \u{3000}", "\u{a0}a"]),
    ("\u{2028} \r\n\u{3000}a", ["\u{2028} \r\n", "\u{3000}a"]),
    ("\u{3000}\u{a0}", ["\u{3000}\u{a0}"]),
    ("\u{2028}a", ["\u{2028}a"]),
    ("\r\na", ["\r\n", "a"]),
    (" !!😀/\r\n///a", [" !!😀/\r\n///", "a"]),
    ("!! /a", ["!!", " /", "a"]),
    ("!\u{2028}/", ["!", "\u{2028}", "/"]),
  ]
  for (text, pieces) in cases {
    assert_eq(pieces.join(""), text)
    let bytes = @utf8.encode(text)
    let mut start = 0
    for piece in pieces {
      let expected = @utf8.encode(piece)
      let end = encoder.piece_end(bytes, start)
      assert_eq(end, start + expected.length(), msg=text)
      assert_eq(bytes[start:end], expected[:], msg=text)
      start = end
    }
    assert_eq(start, bytes.length(), msg=text)
  }
}

///|
test "UTF-8 scalar decoder preserves width transitions, BOM and noncharacters" {
  // Explicit UTF-8 encodings and scalar boundaries, not scanner-derived data.
  let bytes = b"\x00\x7f\xc2\x80\xdf\xbf\xe0\xa0\x80\xed\x9f\xbf\xee\x80\x80\xef\xbb\xbf\xef\xbf\xbe\xef\xbf\xbf\xf0\x90\x80\x80\xf4\x8f\xbf\xbf"
  let boundaries = [0, 1, 2, 4, 6, 9, 12, 15, 18, 21, 24, 28, 32]
  let scalars = [
    0, 0x7f, 0x80, 0x7ff, 0x800, 0xd7ff, 0xe000, 0xfeff, 0xfffe, 0xffff, 0x10000,
    0x10ffff,
  ]
  for i in 0..<scalars.length() {
    assert_eq(scalar_at(bytes, boundaries[i]), scalars[i])
    assert_eq(scalar_width(scalars[i]), boundaries[i + 1] - boundaries[i])
  }
  assert_eq(@utf8.encode(@utf8.decode(bytes)), bytes)
  let encoder = single_byte_encoder_for_test()
  assert_eq(
    encoder.encode(@utf8.decode(bytes)),
    [
      for b in bytes => b.to_int()
    ],
  )
  assert_eq(encoder.count(@utf8.decode(bytes)), bytes.length())
}

///|
// A complete single-byte vocabulary ensures the malformed-string tests below
// cannot pass accidentally due to missing ranks or an undersized category table.
fn single_byte_encoder_for_test() -> Encoder {
  let ranks : Map[Bytes, Int32] = Map([])
  for i in 0..<256 {
    ranks[Bytes::from_array([i.to_byte()])] = i
  }
  { ranks, categories: FixedArray::make(0x110000, b'\x00'), native: None, }
}

///|
test "valid constructed surrogate pairs and replacement scalars retain bytes" {
  let encoder = single_byte_encoder_for_test()
  let high = "😀".unsafe_substring(start=0, end=1)
  let low = "😀".unsafe_substring(start=1, end=2)
  assert_eq(encoder.encode(high + low), [0xf0, 0x9f, 0x98, 0x80])
  assert_eq(encoder.count(high + low), 4)
  assert_eq(encoder.encode("a�b"), [97, 0xef, 0xbf, 0xbd, 98])
}

///|
test "panic encode rejects isolated leading surrogate" {
  ignore(
    single_byte_encoder_for_test().encode(
      "😀".unsafe_substring(start=0, end=1),
    ),
  )
}

///|
test "panic count rejects isolated trailing surrogate" {
  ignore(
    single_byte_encoder_for_test().count(
      "😀".unsafe_substring(start=1, end=2),
    ),
  )
}

///|
test "panic encode rejects interior trailing surrogate" {
  ignore(
    single_byte_encoder_for_test().encode(
      "a" + "😀".unsafe_substring(start=1, end=2) + "b",
    ),
  )
}

///|
test "panic count rejects interior leading surrogate" {
  ignore(
    single_byte_encoder_for_test().count(
      "a" + "😀".unsafe_substring(start=0, end=1) + "b",
    ),
  )
}
