///|
#borrow(counter, text)
extern "c" fn native_piece_end(
  counter : NativeCounter,
  text : Bytes,
  start : Int32,
) -> Int32 = "moon_repomix_counter_piece_end"

///|
priv struct NativeGolden {
  name : String
  text : String
  ids : Array[Int32]
} derive(FromJson)

///|
async fn native_test_assets() -> String {
  match @env.get_env_var("TOKENIZER_ASSETS") {
    Some(path) => path
    None => @fs.realpath("assets")
  }
}

///|
fn require_native(encoder : Encoder) -> NativeCounter raise {
  let counter = match encoder.native {
    Some(counter) => counter
    None => abort("native handle missing")
  }
  assert_eq(native_counter_count(counter, b"hello"), 1)
  counter
}

///|
fn assert_native_differential(encoder : Encoder, text : String) -> Unit raise {
  let counter = match encoder.native {
    Some(counter) => counter
    None => abort("native handle missing")
  }
  let bytes = @utf8.encode(text)
  let mut start = 0
  while start < bytes.length() {
    let expected = encoder.piece_end(bytes, start)
    assert_eq(native_piece_end(counter, bytes, start), expected)
    start = expected
  }
  let expected = encoder.encode(text).length()
  assert_eq(encoder.encode_text(text, None), expected)
  // Do not let the public fallback hide a native failure in these assertions.
  assert_eq(native_counter_count(counter, bytes), expected)
  assert_eq(encoder.count(text), expected)
}

///|
async test "native count and byte boundaries match all 104 independent ID goldens and both MoonBit paths" {
  let assets = native_test_assets()
  let encoder = Encoder::load(assets + "/tokenizer-o200k_base.tiktoken")
  let counter = require_native(encoder)
  let cases : Array[NativeGolden] = @json.from_json(
    @json.parse(@fs.read_file(assets + "/tokenizer-golden.json").text()),
  )
  assert_eq(cases.length(), 104)
  for case in cases {
    assert_eq(encoder.encode(case.text), case.ids, msg=case.name)
    assert_eq(
      native_counter_count(counter, @utf8.encode(case.text)),
      case.ids.length(),
      msg=case.name,
    )
    assert_native_differential(encoder, case.text)
  }
}

///|
async test "native ordered alternatives Unicode widths NUL and deterministic mixed texts" {
  let encoder = Encoder::load(
    native_test_assets() + "/tokenizer-o200k_base.tiktoken",
  )
  ignore(require_native(encoder))
  for
    text in [
      "",
      "!",
      "!!!",
      "!?!?!?!",
      "\u{0}",
      "\u{0}a\u{0}!!\u{0}",
      "<|endoftext|><|endofprompt|>",
      " Aé猫𐐨!",
      "😀Hello",
      "猫A",
      "\u{0301}A",
      "\u{0301}",
      "!ABCdef",
      "!ABC",
      "aB",
      "²Ⅷ𝟛4",
      "١２𝟛4",
      "é'ſX",
      "a'RE",
      "a'ré",
      "a'r",
      "a'",
      "A'LLé",
      " \u{3000}\u{a0}!",
      " \u{3000}\u{a0}a",
      "\u{2028} \r\n\u{3000}a",
      "\u{3000}\u{a0}",
      "\u{2028}a",
      "\r\na",
      " !!😀/\r\n///a",
      "!! /a",
      "!\u{2028}/",
      "\u{feff}\u{fffe}\u{ffff}\u{10ffff}",
      "𐐀𐐨\u{0301}'ſ 𝟛١Ⅷ²",
      "😀".unsafe_substring(start=0, end=1) +
      "😀".unsafe_substring(start=1, end=2),
    ] {
    assert_native_differential(encoder, text)
  }
  let alphabet = [
    "a", "B", "猫", "𐐨", "𐐀", "\u{0301}", "\u{0903}", "ſ", "'", "r", "E",
    "l", "L", "0", "²", "Ⅷ", "𝟛", "١", "\u{0}", "\u{7f}", "!", "/", "😀",
    "\u{200d}", " ", "\t", "\r", "\n", "\u{85}", "\u{a0}", "\u{2028}", "\u{3000}",
    "\u{feff}", "\u{10ffff}",
  ]
  let mut state = 0x12345678U
  for _ in 0..<64 {
    let text = StringBuilder()
    for _ in 0..<256 {
      state = state * 1664525U + 1013904223U
      text.write_string(
        alphabet[(state % alphabet.length().reinterpret_as_uint()).reinterpret_as_int()],
      )
    }
    assert_native_differential(encoder, text.to_string())
  }
  // Sweep the scalar range with surrounding overlapping letter/number classes.
  for cp = 0; cp <= 0x10ffff; cp = cp + 3979 {
    if cp < 0xd800 || cp > 0xdfff {
      let scalar = String::from_array([cp.unsafe_to_char()])
      assert_native_differential(
        encoder,
        " A" + scalar + "a'ſ /" + scalar + "1234",
      )
    }
  }
}

///|
async test "native long pieces memo saturation repetition handle reuse and exact fallback" {
  let assets = native_test_assets()
  let encoder = Encoder::load(assets + "/tokenizer-o200k_base.tiktoken")
  let counter = require_native(encoder)
  for
    text in [
      " ".repeat(4096),
      "\u{3000}".repeat(2048) + "a",
      "\r\n \t".repeat(2048),
      "!?/".repeat(4096),
      "ab".repeat(8192),
      "a".repeat(255),
      "a".repeat(256),
      "a".repeat(257),
      "antidisestablishmentarianism 中文 😀\u{0}\n".repeat(512),
    ] {
    assert_native_differential(encoder, text)
    assert_eq(
      native_counter_count(counter, @utf8.encode(text)),
      encoder.count(text),
    )
  }
  let text = StringBuilder()
  // 8,400 distinct ordinary word pieces exceed the 8,192-key memo cap; repeat
  // both early and late keys after saturation, then reuse the same handle.
  for _ in 0..<2 {
    for i in 0..<8400 {
      let word = String::from_array([
        (97 + i / 676).unsafe_to_char(),
        (97 + i / 26 % 26).unsafe_to_char(),
        (97 + i % 26).unsafe_to_char(),
      ])
      text.write_string(" memokey" + word)
    }
  }
  assert_native_differential(encoder, text.to_string())
  assert_native_differential(encoder, "hello \u{0}! a'LL 😀")
  // Unsupported scratch size must not be confused with zero or approximation.
  let oversized = "\u{1}".repeat(1048577)
  assert_eq(native_counter_count(counter, @utf8.encode(oversized)), -1)
  assert_eq(encoder.encode_text(oversized, None), 1048577)
  assert_eq(encoder.count(oversized), 1048577)
  // Simulate an unavailable native allocation with an empty private resource.
  // The public loader still performs every strict validation before this FFI.
  let fallback : Encoder = {
    ranks: encoder.ranks,
    categories: encoder.categories,
    native: Some(native_counter_new(b"", b"")),
  }
  for text in ["", "!", "\u{0}", "hello 世界 😀", "a'ſ\r\n"] {
    assert_eq(fallback.count(text), encoder.encode(text).length())
  }
  for _ in 0..<4 {
    let another = Encoder::load(assets + "/tokenizer-o200k_base.tiktoken")
    ignore(require_native(another))
    assert_native_differential(
      another, "\u{0} hello HELLO a'ſ 𝟛١Ⅷ² !?!",
    )
  }
}

///|
async test "panic native count rejects isolated leading surrogate" {
  let encoder = Encoder::load(
    native_test_assets() + "/tokenizer-o200k_base.tiktoken",
  )
  ignore(require_native(encoder))
  ignore(encoder.count("😀".unsafe_substring(start=0, end=1)))
}

///|
async test "panic native count rejects interior trailing surrogate" {
  let encoder = Encoder::load(
    native_test_assets() + "/tokenizer-o200k_base.tiktoken",
  )
  ignore(require_native(encoder))
  ignore(encoder.count("a" + "😀".unsafe_substring(start=1, end=2) + "b"))
}
