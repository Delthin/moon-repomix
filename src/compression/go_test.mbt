///|
test "Go AST generics, receiver signatures, complete types and nested definitions" {
  let source =
    #|// Package api 文档 😀
    #|package api
    #|import "io"
    #|type Number interface { ~int | ~int64 }
    #|type Box[T Number] struct { Value T; Label string `json:"label"` }
    #|type Reader = io.Reader
    #|type Handler func(name string, rest ...int) (int, error)
    #|const Version = "1.0"
    #|var callback = func(x int) int { return x + 123456789 }
    #|func Map[T Number, R any](input []T, convert func(T) R) (out []R, err error) {
    #|  // Kept inside implementation
    #|  type Local struct { Name string; Read func([]byte) (int, error) }
    #|  if len(input) > 0 {
    #|    type Alias = Local
    #|    nested := func(value T) R { panic("nested implementation details") }
    #|    _ = nested
    #|  }
    #|  raw := `func fake() { not a definition }`
    #|  _ = raw
    #|  return nil, nil
    #|}
    #|func (b *Box[T]) Get(label string, rest ...T) (value T, err error) {
    #|  /* retained block comment */
    #|  value = b.Value + 987654321
    #|  return value, nil
    #|}
    #|// Bodyless assembly declaration
    #|func native(value int) int
    #|
  let out = @compression.compress("api.GO", source)
  assert_eq(out.language, Some("go"))
  assert_true(out.applied)
  assert_eq(out.reason, None)
  for
    anchor in [
      "// Package api 文档 😀", "package api", "import \"io\"", "type Number interface { ~int | ~int64 }",
      "type Box[T Number] struct { Value T; Label string `json:\"label\"` }", "type Reader = io.Reader",
      "type Handler func(name string, rest ...int) (int, error)", "const Version = \"1.0\"",
      "var callback = func(x int) int {", "func Map[T Number, R any](input []T, convert func(T) R) (out []R, err error)",
      "// Kept inside implementation", "type Local struct { Name string; Read func([]byte) (int, error) }",
      "type Alias = Local", "nested := func(value T) R {", "func (b *Box[T]) Get(label string, rest ...T) (value T, err error)",
      "/* retained block comment */", "func native(value int) int",
    ] {
    assert_true(out.text.contains(anchor), msg=anchor)
  }
  for
    detail in [
      "123456789", "987654321", "nested implementation details", "func fake", "return nil",
      "if len(input)",
    ] {
    assert_false(out.text.contains(detail), msg=detail)
  }
}

///|
test "Go exact original CRLF ranges, non-smaller types, invalid and unsupported fallback" {
  let source = "// 文档 😀\r\npackage api\r\nfunc Get(value int) (int, error) {\r\n  result := value + 123456789\r\n  return result, nil\r\n}\r\n"
  let out = @compression.compress("api.go", source)
  assert_true(out.applied)
  assert_eq(
    out.text,
    "// 文档 😀\r\npackage api\r\nfunc Get(value int) (int, error) {/* … */\r\n}\r\n",
  )
  assert_eq(out.ranges, [
    { start_line: 1, end_line: 3, },
    { start_line: 6, end_line: 6, },
  ])
  for
    source in [
      "package api\ntype R interface { Read([]byte) (int, error) }\ntype Alias = R\n",
      "package api\nfunc noop() {}\n",
    ] {
    let unchanged = @compression.compress("types.go", source)
    assert_false(unchanged.applied)
    assert_eq(unchanged.reason, Some("not-smaller"))
    assert_eq(unchanged.text, source)
    assert_eq(unchanged.ranges, [])
  }
  let invalid = "package api\nfunc broken( {"
  let fallback = @compression.compress("invalid.go", invalid)
  assert_eq(fallback.language, Some("go"))
  assert_eq(fallback.reason, Some("parse-error"))
  assert_false(fallback.applied)
  assert_eq(fallback.text, invalid)
  assert_eq(fallback.ranges, [])
  let unsupported = @compression.compress("api.go.txt", source)
  assert_eq(unsupported.language, None)
  assert_eq(unsupported.reason, Some("unsupported"))
  assert_false(unsupported.applied)
  assert_eq(unsupported.text, source)
  assert_eq(unsupported.ranges, [])
}
