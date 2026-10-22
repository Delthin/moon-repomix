///|
test "MoonBit AST declarations, effects, async, nested functions and literal boundaries" {
  let source =
    #|import { "moonbitlang/core/string" @string }
    #|///| API 文档 😀
    #|pub(all) struct Point { x : Int; y : Int } derive(Eq, Show)
    #|priv enum State { Ready; Failed(String) } derive(Eq)
    #|pub type Handle
    #|pub typealias Int as Count
    #|pub trait Render { render(Self, label~ : String) -> String raise Error }
    #|pub const Limit : Int = 100
    #|#cfg(target="native")
    #|pub async fn[T : Show] Point::render(self : Point, value : T, label~ : String = "文档 { }") -> String raise Error {
    #|  guard self.x > 0 else { raise Failure("implementation failure") }
    #|  let updated = { ..self, x: 42 }
    #|  fn normalize(value : String) -> String noraise {
    #|    value + "nested implementation details"
    #|  }
    #|  struct Local { name : String }
    #|  enum LocalState { Yes; No }
    #|  type LocalId = Int
    #|  fn choose { value => value + 55555555 }
    #|  if updated.x > 10 {
    #|    fn branch(value : Int) -> Int { value + 987654321 }
    #|  }
    #|  let raw =
    #|    #| { // this is literal content, not a comment
    #|    #| fn fake() { not a declaration }
    #|  let template =
    #|    $|result \{normalize(label)} { braces }
    #|  normalize(raw + template + value.to_string())
    #|}
    #|pub impl Render for Point with render(self, label~) -> String raise Error {
    #|  label + "implementation rendering details"
    #|}
    #|async test "async case" {
    #|  let ignored = "implementation test details"
    #|  ignore(ignored)
    #|}
    #|pub fn default_callback(callback~ : (Int) -> Int = fn(value) { value + 789 }) -> Int {
    #|  callback(99999999)
    #|}
    #|extern "c" fn native_call(value : Int) -> Int = "native_call_implementation"
    #|extern "wasm" fn imported_call(value : Int) -> Int = "module" "field"
    #|extern "js" fn inline_call(value : Int) -> Int =
    #|  #| (value) => value + 1234567 // inline external implementation details
    #|priv fn tuples_and_cleanup(pairs : Array[(Int, Int)], value : Int) -> Bool {
    #|  errdefer { ignore("cleanup implementation details") }
    #|  for (left, right) in pairs {
    #|    fn tuple_local(input : Int) -> Int { input + 123456789 }
    #|    ignore(tuple_local(left + right))
    #|  }
    #|  match value { 1..<=3 => true; _ => false }
    #|}
    #|
  let out = @compression.compress("outline.MBT", source)
  assert_eq(out.language, Some("moonbit"))
  assert_eq(out.reason, None)
  assert_true(out.applied)
  for
    anchor in [
      "import {", "///| API 文档 😀", "pub(all) struct Point { x : Int; y : Int } derive(Eq, Show)",
      "priv enum State", "pub type Handle", "pub typealias Int as Count", "pub trait Render",
      "pub const Limit : Int = 100", "#cfg(target=\"native\")", "pub async fn[T : Show] Point::render",
      "label~ : String = \"文档 { }\") -> String raise Error", "fn normalize(value : String) -> String noraise",
      "struct Local", "enum LocalState", "type LocalId = Int", "fn choose", "fn branch(value : Int) -> Int",
      "pub fn default_callback(callback~ : (Int) -> Int = fn(value) { value + 789 }) -> Int",
      "pub impl Render for Point with render(self, label~) -> String raise Error",
      "async test \"async case\"", "extern \"c\" fn native_call(value : Int) -> Int = \"native_call_implementation\"",
      "extern \"wasm\" fn imported_call(value : Int) -> Int = \"module\" \"field\"",
      "extern \"js\" fn inline_call(value : Int) -> Int =", "priv fn tuples_and_cleanup(pairs : Array[(Int, Int)], value : Int) -> Bool",
      "fn tuple_local(input : Int) -> Int",
    ] {
    assert_true(out.text.contains(anchor), msg=anchor)
  }
  for
    implementation in [
      "guard self.x", "{ ..self", "nested implementation", "987654321", "55555555",
      "99999999", "fn fake", "this is literal content", "result ", "implementation rendering",
      "implementation test", "inline external implementation details", "cleanup implementation",
      "errdefer", "for (left, right)", "1..<=3", "input + 123456789",
    ] {
    assert_false(out.text.contains(implementation), msg=implementation)
  }
  assert_true(out.text.length() < source.length())
}

///|
test "MoonBit interfaces, exact CRLF ranges and honest syntax fallback" {
  let source = "///| 文档 😀\r\npub fn Point::get(self : Point) -> Int raise Error {\r\n  let result = self.x + 123456789\r\n  result\r\n}\r\n"
  let out = @compression.compress("point.mbt", source)
  assert_true(out.applied)
  assert_eq(
    out.text,
    "///| 文档 😀\r\npub fn Point::get(self : Point) -> Int raise Error {/* … */\r\n}\r\n",
  )
  assert_eq(out.ranges, [
    { start_line: 1, end_line: 2, },
    { start_line: 5, end_line: 5, },
  ])
  let interface =
    #|package "example/point"
    #|import { "moonbitlang/core/string" }
    #|pub(all) struct Point { x : Int; y : Int }
    #|pub fn[T : Show] Point::get(Self, label~ : String) -> T raise Error
    #|pub async fn fetch(String) -> String
    #|pub trait Render { render(Self) -> String }
    #|pub impl Render for Point
    #|pub let origin : Point
    #|
  for path in ["point.mbti", "POINT.MBTI"] {
    let unchanged = @compression.compress(path, interface)
    assert_eq(unchanged.language, Some("moonbit"))
    assert_eq(unchanged.reason, Some("not-smaller"))
    assert_false(unchanged.applied)
    assert_eq(unchanged.text, interface)
    assert_eq(unchanged.ranges, [])
  }
  for
    invalid in [
      "pub fn broken( {", "fn broken() { let value = #~not a MoonBit multiline string\n value }",
    ] {
    let fallback = @compression.compress("invalid.mbt", invalid)
    assert_eq(fallback.language, Some("moonbit"))
    assert_eq(fallback.reason, Some("parse-error"))
    assert_false(fallback.applied)
    assert_eq(fallback.text, invalid)
    assert_eq(fallback.ranges, [])
  }
}
