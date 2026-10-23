///|
test "Rust AST types, impls, lifetime where signatures, nested items and opaque macros" {
  let source =
    #|#![allow(dead_code)]
    #|//! API 文档 😀
    #|use core::fmt::{self, Display};
    #|pub mod external;
    #|#[derive(Clone)]
    #|pub struct View<'a, T: Display> where T: 'a { pub value: &'a T, count: usize }
    #|pub enum State<T> { Ready(T), Error { code: u32 } }
    #|pub union Bits { pub signed: i32, pub unsigned: u32 }
    #|pub type Alias<'a, T> = &'a T;
    #|pub trait Render<'a>: Display where Self: 'a {
    #|    type Output: Display;
    #|    const LIMIT: usize;
    #|    fn signature(&'a self, value: &'a str) -> Self::Output;
    #|    /// Default rendering
    #|    fn render(&'a self) -> usize { let value = 123456789; value }
    #|}
    #|impl<'a, T: Display> Render<'a> for View<'a, T> where T: 'a {
    #|    type Output = String;
    #|    const LIMIT: usize = 100;
    #|    #[inline]
    #|    fn signature(&'a self, value: &'a str) -> Self::Output {
    #|        // retained inside implementation
    #|        let result = String::from(value);
    #|        result
    #|    }
    #|}
    #|extern "C" { pub fn native(value: *const u8, len: usize) -> i32; pub static FLAG: i32; }
    #|macro_rules! make_api { ($name:ident) => { pub fn $name() { untouched_tokens!(); } }; }
    #|make_api!(generated);
    #|pub mod inner {
    #|    #[must_use]
    #|    pub const unsafe extern "C" fn calculate<T>(value: T) -> usize where T: Copy {
    #|        if true {
    #|            #[derive(Debug)]
    #|            struct Local { value: usize }
    #|            #[inline]
    #|            fn nested<'b>(text: &'b str) -> &'b str { let ignored = 987654321; text }
    #|            macro_rules! local_api { () => { pub struct Generated; }; }
    #|            local_api!();
    #|        }
    #|        let raw = r###"fn fake() { /* not a comment */ }"###;
    #|        456789012
    #|    }
    #|}
    #|
  let out = @compression.compress("api.RS", source)
  assert_eq(out.language, Some("rust"))
  assert_eq(out.reason, None)
  assert_true(out.applied)
  for
    anchor in [
      "#![allow(dead_code)]", "//! API 文档 😀", "use core::fmt::{self, Display};",
      "pub mod external;", "#[derive(Clone)]", "pub struct View<'a, T: Display> where T: 'a { pub value: &'a T, count: usize }",
      "pub enum State<T> { Ready(T), Error { code: u32 } }", "pub union Bits { pub signed: i32, pub unsigned: u32 }",
      "pub type Alias<'a, T> = &'a T;", "pub trait Render<'a>: Display where Self: 'a {",
      "type Output: Display;", "const LIMIT: usize;", "fn signature(&'a self, value: &'a str) -> Self::Output;",
      "/// Default rendering", "fn render(&'a self) -> usize {", "impl<'a, T: Display> Render<'a> for View<'a, T> where T: 'a {",
      "type Output = String;", "const LIMIT: usize = 100;", "#[inline]", "// retained inside implementation",
      "extern \"C\" { pub fn native(value: *const u8, len: usize) -> i32; pub static FLAG: i32; }",
      "macro_rules! make_api { ($name:ident) => { pub fn $name() { untouched_tokens!(); } }; }",
      "make_api!(generated);", "pub mod inner {", "#[must_use]", "pub const unsafe extern \"C\" fn calculate<T>(value: T) -> usize where T: Copy",
      "#[derive(Debug)]", "struct Local { value: usize }", "fn nested<'b>(text: &'b str) -> &'b str",
      "macro_rules! local_api { () => { pub struct Generated; }; }", "local_api!()",
    ] {
    assert_true(out.text.contains(anchor), msg=anchor)
  }
  for
    detail in [
      "123456789", "987654321", "456789012", "String::from(value)", "if true", "fn fake",
      "not a comment",
    ] {
    assert_false(out.text.contains(detail), msg=detail)
  }
}

///|
test "Rust exact original CRLF ranges, macro and extern non-smaller, syntax fallback" {
  let source = "/// 文档 😀\r\n#[inline]\r\npub fn get<'a>(value: &'a str) -> &'a str {\r\n  let ignored = 123456789;\r\n  value\r\n}\r\n"
  let out = @compression.compress("api.rs", source)
  assert_true(out.applied)
  assert_eq(
    out.text,
    "/// 文档 😀\r\n#[inline]\r\npub fn get<'a>(value: &'a str) -> &'a str {/* … */\r\n}\r\n",
  )
  assert_eq(out.ranges, [
    { start_line: 1, end_line: 3, },
    { start_line: 6, end_line: 6, },
  ])
  for
    source in [
      "pub struct Api<T> { pub field: T }\npub trait Read { type Value; fn read(&self) -> Self::Value; }\n",
      "extern \"C\" { pub fn native(value: usize) -> usize; }\n", "macro_rules! api { () => { pub fn generated() { 123456789; } }; }\napi!();\n",
      "pub const VALUE: usize = { let value = 123456789; value };\n",
    ] {
    let unchanged = @compression.compress("types.rs", source)
    assert_false(unchanged.applied)
    assert_eq(unchanged.reason, Some("not-smaller"))
    assert_eq(unchanged.text, source)
    assert_eq(unchanged.ranges, [])
  }
  let invalid = "pub fn broken( {"
  let fallback = @compression.compress("invalid.rs", invalid)
  assert_eq(fallback.language, Some("rust"))
  assert_eq(fallback.reason, Some("parse-error"))
  assert_false(fallback.applied)
  assert_eq(fallback.text, invalid)
  assert_eq(fallback.ranges, [])
  let unsupported = @compression.compress("api.rs.txt", source)
  assert_eq(unsupported.language, None)
  assert_eq(unsupported.reason, Some("unsupported"))
  assert_false(unsupported.applied)
  assert_eq(unsupported.text, source)
  assert_eq(unsupported.ranges, [])
}
