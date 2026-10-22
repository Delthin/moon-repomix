///|
async test "byte ranks parser matches every core-decoded resource record and rejects malformed data" {
  let assets = match @env.get_env_var("TOKENIZER_ASSETS") {
    Some(path) => path
    None => @fs.realpath("assets")
  }
  let path = assets + "/tokenizer-o200k_base.tiktoken"
  // The reference deliberately retains the previous UTF-8/split/core decoder
  // path, independently of the byte parser and bounded reader under test.
  let reference_bytes = @fs.read_file(path).binary()
  let snapshot = read_resource(path, 3613922)
  assert_eq(snapshot, reference_bytes)
  let actual = read_ranks(snapshot)
  let mut records = 0
  for line in @utf8.decode(reference_bytes).split("\n") {
    if line.is_empty() {
      continue
    }
    let fields = line.split(" ").collect()
    assert_eq(fields.length(), 2)
    let token = @base64.decode(fields[0])
    let rank = @string.parse_int(fields[1])
    assert_eq(actual.get(token), Some(rank), msg="rank \{rank}")
    records += 1
  }
  assert_eq(records, 199998)
  assert_eq(actual.length(), records)
  for valid in ["", "YQ", "YQ==", "YWI", "YWI=", "YWJj", "/w==", "+/8="] {
    assert_eq(read_rank_token(@utf8.encode(valid)), @base64.decode(valid))
  }
  for
    invalid in [
      "A", "AA=", "AA===", "====", "AA=A", "AA==AA==", "AB==", "AAB=", "AB", "AAB",
      "AA A", "AA\tA", "AA\r", "AAÿ", "AA-_",
    ] {
    try read_rank_token(@utf8.encode(invalid)) catch {
      ResourceError(message) => assert_eq(message, "invalid o200k Base64 token")
      error => raise error
    } noraise {
      _ => fail("accepted invalid Base64: \{invalid}")
    }
  }
  for
    (invalid, expected) in [
      ("YQ==", "invalid o200k ranks record"),
      ("YQ==\n", "invalid o200k ranks record"),
      ("YQ== \n", "invalid o200k decimal rank"),
      ("YQ== 0 1\n", "invalid o200k decimal rank"),
      ("YQ== -1\n", "invalid o200k decimal rank"),
      ("YQ== 2147483648\n", "invalid o200k decimal rank"),
      ("YQ== 1\n", "invalid o200k rank sequence"),
      ("YQ== 0\nYQ== 1\n", "invalid o200k rank sequence"),
      ("YQ== 0", "incomplete o200k ranks"),
      ("\nYQ== 0\n\n", "incomplete o200k ranks"),
    ] {
    try read_ranks(@utf8.encode(invalid)) catch {
      ResourceError(message) => assert_eq(message, expected)
      error => raise error
    } noraise {
      _ => fail("accepted invalid ranks: \{invalid}")
    }
  }
  // Read through the public streaming API even when the bound is shorter than
  // the resource: retain exactly one extra byte for checksum rejection.
  assert_eq(read_resource(path, 17), reference_bytes[:18].to_owned())
}
