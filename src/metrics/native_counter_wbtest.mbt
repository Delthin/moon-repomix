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
fn assert_native_differential(
  encoder : Encoder,
  text : String,
  session : CountSession,
) -> Unit raise {
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
  let storage = match session.native {
    Some(storage) => storage
    None => abort("native session missing")
  }
  assert_eq(native_session_count(storage, counter, bytes), expected)
  assert_eq(session.count(text), expected)
}

///|
async fn session_outside_owner_scope(assets : String) -> CountSession {
  let owner = Encoder::load(assets + "/tokenizer-o200k_base.tiktoken")
  owner.session()
}

///|
async test "native count and byte boundaries match independent ID goldens and both MoonBit paths" {
  let assets = native_test_assets()
  let encoder = Encoder::load(assets + "/tokenizer-o200k_base.tiktoken")
  let counter = require_native(encoder)
  let session = encoder.session()
  let cases : Array[NativeGolden] = @json.from_json(
    @json.parse(@fs.read_file(assets + "/tokenizer-golden.json").text()),
  )
  for case in cases {
    assert_eq(
      native_counter_count(counter, @utf8.encode(case.text)),
      case.ids.length(),
      msg=case.name,
    )
    assert_native_differential(encoder, case.text, session)
  }
  let independent = encoder.session()
  // Reordered complete documents reuse one memo without sharing it with the
  // second session; neither count assumes additive or monotonic documents.
  for i = cases.length() - 1; i >= 0; i = i - 1 {
    assert_eq(session.count(cases[i].text), cases[i].ids.length())
    assert_eq(independent.count(cases[i].text), cases[i].ids.length())
  }
}

///|
async test "native ordered alternatives Unicode widths NUL and deterministic mixed texts" {
  let encoder = Encoder::load(
    native_test_assets() + "/tokenizer-o200k_base.tiktoken",
  )
  ignore(require_native(encoder))
  let session = encoder.session()
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
    assert_native_differential(encoder, text, session)
  }
  // ASCII-only upper*/lower* fast exits, optional one-byte prefixes, and
  // non-ASCII extensions must keep the original ordered Unicode boundaries.
  for prefix in ["", " ", "!", "\u{0}", "\t", "\r", "\n", "1"] {
    for word in ["a", "ABC", "ABCdef", "abCD"] {
      for
        edge in [
          "", "é", "İ", "ǅ", "ʰ", "猫", "\u{0301}", "\u{0903}", "𐐨", "😀",
          "'ſ", "'RE", "'lL", "'ré", "\u{2028}",
        ] {
        assert_native_differential(
          encoder,
          prefix + word + edge + "aB!",
          session,
        )
      }
    }
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
    assert_native_differential(encoder, text.to_string(), session)
  }
  // Sweep the scalar range with surrounding overlapping letter/number classes.
  for cp = 0; cp <= 0x10ffff; cp = cp + 3979 {
    if cp < 0xd800 || cp > 0xdfff {
      let scalar = String::from_array([cp.unsafe_to_char()])
      assert_native_differential(
        encoder,
        " A" + scalar + "a'ſ /" + scalar + "1234",
        session,
      )
    }
  }
}

///|
async test "native long pieces memo saturation repetition handle reuse and exact fallback" {
  let assets = native_test_assets()
  let encoder = Encoder::load(assets + "/tokenizer-o200k_base.tiktoken")
  let counter = require_native(encoder)
  let session = encoder.session()
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
    assert_native_differential(encoder, text, session)
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
  assert_native_differential(encoder, text.to_string(), session)
  assert_native_differential(encoder, "hello \u{0}! a'LL 😀", session)
  // A fresh document after saturation must still be completely scanned/BPE'd.
  for _ in 0..<3 {
    for document in [" memokeyaaa", " memokeymkb", " newlateword", "", "hello!"] {
      assert_native_differential(encoder, document, session)
    }
  }
  // Alternate late document vocabularies after saturation; their memo contents
  // may replace earlier pieces, but every full document must match both oracles.
  for round in 0..<3 {
    let later = StringBuilder()
    for i in 0..<256 {
      let word = String::from_array([
        (97 + round).unsafe_to_char(),
        (97 + i / 26).unsafe_to_char(),
        (97 + i % 26).unsafe_to_char(),
      ])
      later.write_string(" clockword" + word + "'ſ\u{0}Aé")
    }
    let document = later.to_string()
    assert_native_differential(encoder, document, session)
    assert_native_differential(encoder, document, session)
  }
  assert_eq(session.count("a") + session.count("b"), 2)
  assert_eq(session.count("ab"), 1)
  assert_eq(session.count(""), 0)
  // Unsupported scratch size must not be confused with zero or approximation.
  let oversized = "\u{1}".repeat(1048577)
  assert_eq(native_counter_count(counter, @utf8.encode(oversized)), -1)
  assert_eq(encoder.encode_text(oversized, None), 1048577)
  assert_eq(encoder.count(oversized), 1048577)
  let storage = match session.native {
    Some(storage) => storage
    None => abort("native session missing")
  }
  assert_eq(native_session_count(storage, counter, @utf8.encode(oversized)), -1)
  assert_eq(session.count(oversized), 1048577)
  assert_native_differential(
    encoder, "hello 😀 after failed document", session,
  )
  assert_eq(session.count(""), 0)
  // Simulate an unavailable native allocation with an empty private resource.
  // The public loader still performs every strict validation before this FFI.
  let fallback : Encoder = {
    ranks: encoder.ranks,
    categories: encoder.categories,
    native: Some(native_counter_new(b"", b"")),
  }
  let legacy : Encoder = {
    ranks: encoder.ranks,
    categories: encoder.categories,
    native: None,
  }
  let unavailable : CountSession = { owner: encoder, native: None, }
  let fallback_session = fallback.session()
  let legacy_session = legacy.session()
  let scoped = session_outside_owner_scope(assets)
  for _ in 0..<3 {
    for text in ["", "!", "\u{0}", "hello 世界 😀", "a'ſ\r\n"] {
      let expected = encoder.encode(text).length()
      assert_eq(fallback.count(text), expected)
      assert_eq(fallback_session.count(text), expected)
      assert_eq(legacy_session.count(text), expected)
      assert_eq(unavailable.count(text), expected)
      assert_eq(scoped.count(text), expected)
    }
  }
  for _ in 0..<4 {
    let another = Encoder::load(assets + "/tokenizer-o200k_base.tiktoken")
    ignore(require_native(another))
    assert_native_differential(
      another,
      "\u{0} hello HELLO a'ſ 𝟛١Ⅷ² !?!",
      another.session(),
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

///|
async test "panic count session rejects malformed UTF-16 after memo reuse" {
  let session = session_outside_owner_scope(native_test_assets())
  assert_eq(session.count("hello"), 1)
  assert_eq(session.count("hello"), 1)
  ignore(session.count("a" + "😀".unsafe_substring(start=1, end=2) + "b"))
}
