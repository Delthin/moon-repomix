///|
test "checked byte sizes token overflow and ID width" {
  let text = "ASCIIé中😀\r\ne\u0301"
  // 5 + 2 + 3 + 4 + 2 + 1 + 2 UTF-8 bytes.
  assert_eq(byte_length(text), 19)
  assert_eq(volume_id(1), "part-0001")
  assert_eq(volume_id(9999), "part-9999")
  assert_eq(volume_id(10000), "part-10000")
  assert_eq(add_tokens(9223372036854775806L, 1), 9223372036854775807L)
  try add_tokens(9223372036854775806L, 2) catch {
    Overflow(field) => assert_eq(field, "total tokens")
    _ => fail("expected token overflow category")
  } noraise {
    _ => fail("expected checked Int64 overflow")
  }
}
