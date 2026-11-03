///|
fn definition_text(
  source : String,
  definition : @compression.Definition,
) -> String {
  source.split("\n").to_array()[definition.start_line - 1:definition.end_line]
  .map(line => line.to_owned())
  .join("\n")
}

///|
test "definition index JS assignment wrappers, same-name methods and lexical refs" {
  let source =
    #|const LIMIT = 7;
    #|res.render = function render(view) {
    #|  const local = LIMIT;
    #|  return helper(view, local, LIMIT);
    #|};
    #|class Session {
    #|  prepare_request(req) {
    #|    return res.render(req, LIMIT);
    #|  }
    #|}
    #|class Other {
    #|  prepare_request(req) { return helper(req); }
    #|}
    #|function outer() {
    #|  const HIDDEN = 2;
    #|  function inner() { return HIDDEN; }
    #|  return inner();
    #|}
  let index = @compression.index_definitions("api.CJS", source)
  assert_eq(index.reason, None)
  assert_eq(index.definitions.map(d => d.qualified_name), [
    "LIMIT", "res.render", "Session.prepare_request", "Other.prepare_request", "outer",
  ])
  assert_eq(index.definitions.map(d => d.name), [
    "LIMIT", "render", "prepare_request", "prepare_request", "outer",
  ])
  let render = index.definitions[1]
  assert_eq(render.start_line, 2)
  assert_eq(render.end_line, 5)
  assert_eq(
    definition_text(source, render),
    "res.render = function render(view) {\n  const local = LIMIT;\n  return helper(view, local, LIMIT);\n};",
  )
  assert_eq(render.references, ["res", "LIMIT", "helper", "view", "local"])
  assert_eq(index.definitions[2].start_line, 7)
  assert_eq(index.definitions[2].end_line, 9)
  assert_true(index.definitions[2].references.contains("LIMIT"))
  // Property identifiers are lexical candidates too (not a resolved call graph).
  assert_true(index.definitions[2].references.contains("render"))
  let multi_source = "export const FIRST = seed,\n  SECOND = FIRST + other;"
  let multi = @compression.index_definitions("multi.ts", multi_source)
  assert_eq(multi.reason, None)
  assert_eq(multi.definitions.map(d => d.name), ["FIRST", "SECOND"])
  for definition in multi.definitions {
    assert_eq(definition.start_line, 1)
    assert_eq(definition.end_line, 2)
    assert_eq(definition_text(multi_source, definition), multi_source)
    assert_eq(definition.references, ["seed", "FIRST", "other"])
  }
  let patterns = @compression.index_definitions(
    "bindings.js", "const { LIMIT: renamed, ...rest } = config;",
  )
  assert_eq(patterns.reason, None)
  assert_eq(patterns.definitions.map(d => d.name), ["renamed", "rest"])
  assert_eq(patterns.definitions[0].references, ["config"])
  // Same qualified names are preserved too, without suffixes or replacement.
  let duplicates = @compression.index_definitions(
    "same.js", "function foo() { return 1; }\nfunction foo() { return 2; }",
  )
  assert_eq(duplicates.reason, None)
  assert_eq(duplicates.definitions.map(d => d.qualified_name), ["foo", "foo"])
}

///|
test "definition index TS export, decorators, arrow bindings and TSX" {
  let source =
    #|export const LIMIT: number = 7;
    #|export async function fetchValue(x: number): Promise<number> {
    #|  return LIMIT + x;
    #|}
    #|export class Service {
    #|  @memoize
    #|  run(x: number) {
    #|    return fetchValue(x);
    #|  }
    #|  arrow = () => LIMIT;
    #|}
    #|export const read = (): number => LIMIT;
  let index = @compression.index_definitions("service.mts", source)
  assert_eq(index.reason, None)
  assert_eq(index.definitions.map(d => d.qualified_name), [
    "LIMIT", "fetchValue", "Service.run", "Service.arrow", "read",
  ])
  assert_eq(
    definition_text(source, index.definitions[1]),
    "export async function fetchValue(x: number): Promise<number> {\n  return LIMIT + x;\n}",
  )
  assert_eq(index.definitions[2].start_line, 6)
  assert_eq(index.definitions[2].end_line, 9)
  assert_true(index.definitions[2].references.contains("memoize"))
  let tsx = @compression.index_definitions(
    "view.tsx", "export const View = () => (\n  <Panel>{LIMIT}</Panel>\n);",
  )
  assert_eq(tsx.reason, None)
  assert_eq(tsx.definitions[0].qualified_name, "View")
  assert_eq(tsx.definitions[0].start_line, 1)
  assert_eq(tsx.definitions[0].end_line, 3)
  assert_true(tsx.definitions[0].references.contains("LIMIT"))
}

///|
test "definition index Python decorated functions and constants, Unicode and CRLF" {
  let source = "消息 = '😀'\r\nLIMIT = 3\r\n@decorate(消息)\r\nasync def fetch(arg):\r\n    local = LIMIT\r\n    return use(arg, 消息, local)\r\n\r\nclass Session:\r\n    @staticmethod\r\n    def prepare_request(req):\r\n        return fetch(req)\r\n"
  let index = @compression.index_definitions("service.PY", source)
  assert_eq(index.reason, None)
  assert_eq(index.definitions.map(d => d.qualified_name), [
    "消息", "LIMIT", "fetch", "Session.prepare_request",
  ])
  let fetch = index.definitions[2]
  assert_eq(fetch.start_line, 3)
  assert_eq(fetch.end_line, 6)
  assert_eq(
    definition_text(source, fetch),
    "@decorate(消息)\r\nasync def fetch(arg):\r\n    local = LIMIT\r\n    return use(arg, 消息, local)\r",
  )
  assert_eq(fetch.references, [
    "decorate", "消息", "LIMIT", "use", "arg", "local",
  ])
  assert_eq(index.definitions[3].start_line, 9)
  assert_eq(index.definitions[3].end_line, 11)
  let js = @compression.index_definitions(
    "unicode.jsx", "const 消息 = '😀';\r\nexport function 读取() {\r\n  return 消息;\r\n}\r\n",
  )
  assert_eq(js.reason, None)
  assert_eq(js.definitions[1].name, "读取")
  assert_eq(js.definitions[1].start_line, 2)
  assert_eq(js.definitions[1].end_line, 4)
  assert_eq(js.definitions[1].references, ["消息"])
}

///|
test "definition index failures are empty, never partial or hidden truncation" {
  for path in ["file.rs", "file.go", "file.java", "file.txt"] {
    let index = @compression.index_definitions(path, "function okay() {}")
    assert_eq(index.reason, Some("unsupported-language"))
    assert_eq(index.definitions, [])
  }
  for
    (path, source) in [
      ("bad.js", "const OK = 1; function broken( {"),
      ("bad.ts", "export function bad(x: ) {}"),
      ("bad.py", "OK = 1\ndef bad(:\n  pass"),
      ("bad.mbt", "const OK = 1\nfn broken( {"),
      ("bad.mbti", "pub fn broken( -> Int"),
    ] {
    let index = @compression.index_definitions(path, source)
    assert_eq(index.reason, Some("parse-error"))
    assert_eq(index.definitions, [])
  }
  for source in [" ".repeat(8 * 1024 * 1024 + 1), "中".repeat(3 * 1024 * 1024)] {
    let index = @compression.index_definitions("huge.js", source)
    assert_eq(index.reason, Some("resource-limit"))
    assert_eq(index.definitions, [])
  }
  let refs = [ for i in 0..<257 => "ref\{i}" ].join(" + ")
  let index = @compression.index_definitions(
    "refs.js",
    "const OK = 1;\nfunction too_many() { return \{refs}; }",
  )
  assert_eq(index.reason, Some("resource-limit"))
  assert_eq(index.definitions, [])
  let deep = "function deep() { return " +
    "[".repeat(260) +
    "0" +
    "]".repeat(260) +
    "; }"
  let index = @compression.index_definitions("deep.js", deep)
  assert_eq(index.reason, Some("resource-limit"))
  assert_eq(index.definitions, [])
  let empty = @compression.index_definitions("empty.js", "// no definitions\n")
  assert_eq(empty.reason, None)
  assert_eq(empty.definitions, [])
}

///|
fn definition_bytes(
  source : String,
  definition : @compression.Definition,
) -> String {
  let bytes = @utf8.encode(source)
  @utf8.decode_lossy(bytes[definition.start_byte:definition.end_byte])
}

///|
test "definition index extensions agree with routing and return fresh arrays" {
  let extensions = @compression.definition_extensions()
  assert_eq(extensions, [
    ".js", ".jsx", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".tsx", ".py", ".pyi",
    ".mbt", ".mbti",
  ])
  for extension in extensions {
    assert_eq(
      @compression.index_definitions("empty" + extension, "").reason,
      None,
    )
    assert_eq(
      @compression.index_definitions("empty" + extension.to_upper(), "").reason,
      None,
    )
  }
  extensions.clear()
  assert_eq(@compression.definition_extensions().length(), 12)
  assert_eq(@compression.index_definitions("empty.mbt", "").reason, None)
}

///|
test "definition index MoonBit complete bodies, methods, impls and traits" {
  let source =
    #|pub(all) struct Point { x : Int } derive(Eq)
    #|pub trait Render : Show {
    #|  render(Self, label~ : String) -> String
    #|}
    #|pub trait Other { render(Self) -> String }
    #|pub const Limit : Int = 7
    #|#cfg(target="native")
    #|pub async fn[T : Show] Point::render(self : Point, value : T) -> String raise Error {
    #|  let local = Limit
    #|  if local > 0 {
    #|    fn nested() -> Int { local + Limit }
    #|    ignore(nested())
    #|  }
    #|  let raw =
    #|    #| fn fake() { not a definition }
    #|  let template =
    #|    $|result \{value.to_string()} { braces }
    #|  @strings.concat(raw, template)
    #|}
    #|pub impl Render for Point with render(self, label~) -> String {
    #|  label + self.x.to_string()
    #|}
    #|impl Other for Point with render(self) -> String { self.x.to_string() }
    #|impl Render with render(self, label~) -> String { label }
    #|fn render() -> Int { Limit }
    #|fn call(point : Point) -> String {
    #|  Point :: render(point, Limit)
    #|}
    #|extern "c" fn native_call(Int) -> Int = "native_call"
  let index = @compression.index_definitions("fixture.MBT", source)
  assert_eq(index.reason, None)
  assert_eq(index.definitions.map(d => d.qualified_name), [
    "Point", "Render", "Render::render", "Other", "Other::render", "Limit", "Point::render",
    "Render for Point::render", "Other for Point::render", "impl Render::render",
    "render", "call", "native_call",
  ])
  assert_eq(index.definitions.filter(d => d.name == "render").length(), 7)
  let callable = index.definitions[6]
  assert_eq(callable.start_line, 7)
  assert_eq(callable.end_line, 19)
  assert_true(
    definition_bytes(source, callable).has_prefix("#cfg(target=\"native\")"),
  )
  assert_true(definition_bytes(source, callable).contains("if local > 0"))
  assert_true(
    definition_bytes(source, callable).contains(
      "fn nested() -> Int { local + Limit }",
    ),
  )
  assert_true(
    definition_bytes(source, callable).contains(
      "fn fake() { not a definition }",
    ),
  )
  assert_true(callable.references.contains("Limit"))
  assert_true(callable.references.contains("Point"))
  assert_true(callable.references.contains("@strings.concat"))
  assert_false(callable.references.contains("concat"))
  assert_false(callable.references.contains("fake"))
  assert_eq(
    definition_bytes(source, index.definitions[2]),
    definition_bytes(source, index.definitions[1]),
  )
  assert_true(
    definition_bytes(source, index.definitions[2]).contains(
      "trait Render : Show",
    ),
  )
  assert_eq(index.definitions[11].references, [
    "Point", "String", "Point::render", "point", "Limit",
  ])
  assert_false(index.definitions[11].references.contains("render"))
  assert_eq(
    definition_bytes(source, index.definitions[12]),
    "extern \"c\" fn native_call(Int) -> Int = \"native_call\"",
  )
  let constructors = @compression.index_definitions(
    "constructors.mbt", "enum Choice { Item(Int) }\nconst Item = 9\nfn build() { 0 }\nfn make() { Choice::Item(1) }\nfn call() { Choice::build() }",
  )
  assert_eq(constructors.reason, None)
  assert_eq(constructors.definitions[3].references, ["Choice::Item", "Choice"])
  assert_eq(constructors.definitions[4].references, ["Choice::build", "Choice"])
  assert_false(constructors.definitions[3].references.contains("Item"))
  assert_false(constructors.definitions[4].references.contains("build"))
}

///|
test "definition index MoonBit interfaces preserve declarations and exact Unicode CRLF bytes" {
  let source = "///| 文档 😀\r\npub(all) struct Point { x : Int }\r\npub fn Point::get(Self) -> Int\r\npub trait Read { get(Self) -> Int }\r\npub impl Read for Point\r\npub let origin : Point\r\n"
  let index = @compression.index_definitions("point.MBTI", source)
  assert_eq(index.reason, None)
  assert_eq(index.definitions.map(d => d.qualified_name), [
    "Point", "Point::get", "Read", "Read::get", "impl Read for Point", "origin",
  ])
  assert_eq(
    index.definitions[0].start_byte,
    @utf8.encode("///| 文档 😀\r\n").length(),
  )
  assert_eq(index.definitions[1].start_line, 3)
  assert_eq(index.definitions[1].end_line, 3)
  assert_eq(
    definition_bytes(source, index.definitions[1]),
    "pub fn Point::get(Self) -> Int",
  )
  assert_eq(
    definition_bytes(source, index.definitions[4]),
    "pub impl Read for Point",
  )
  assert_eq(index.definitions[1].references, ["Point", "Self", "Int"])
  assert_false(definition_bytes(source, index.definitions[1]).contains("{"))
  assert_false(definition_bytes(source, index.definitions[4]).contains("{"))
  let unicode = @compression.index_definitions(
    "unicode.mbt", "let 消息 = \"😀\"\r\nfn 读取() -> String { 消息 }\r\n",
  )
  assert_eq(unicode.reason, None)
  assert_eq(unicode.definitions.map(d => d.name), ["消息", "读取"])
  assert_eq(unicode.definitions[1].references, ["String", "消息"])
  assert_eq(
    unicode.definitions[1].start_byte,
    @utf8.encode("let 消息 = \"😀\"\r\n").length(),
  )
}

///|
test "definition index MoonBit aliases, extension declarations and duplicate identities" {
  let source =
    #|pub typealias Int as Count
    #|pub typealias Alias = Int
    #|pub typealias @pkg.(Foo as Local, Bar)
    #|pub traitalias Show as Display
    #|pub fnalias @pkg.read as fetch
    #|pub fnalias (first as one, second)
    #|pub extend Point with Render::{render, debug}
    #|fn Point::render(self : Point) -> Int { self.x }
    #|fn Point::render(self : Point) -> Int { self.x + 1 }
    #|impl[T : Show] Render for Array[T] with render(self) -> String { "body" }
    #|pub fnalias Point::render as display
    #|pub typealias Generic[T] = Array[T]
    #|extenum @pkg.State += { Extra }
    #|pub fnalias Point::(render as paint, debug)
  let index = @compression.index_definitions("aliases.mbt", source)
  assert_eq(index.reason, None)
  assert_eq(index.definitions.map(d => d.qualified_name), [
    "Count", "Alias", "Local", "Bar", "Display", "fetch", "one", "second", "Point::render",
    "Point::debug", "Point::render", "Point::render", "Render for Array[T]::render",
    "display", "Generic", "@pkg.State", "paint", "debug",
  ])
  assert_eq(
    definition_bytes(source, index.definitions[2]),
    definition_bytes(source, index.definitions[3]),
  )
  assert_eq(
    definition_bytes(source, index.definitions[8]),
    "pub extend Point with Render::{render, debug}",
  )
  assert_eq(
    index.definitions.filter(d => d.qualified_name == "Point::render").length(),
    3,
  )
  assert_eq(index.definitions[0].references, ["Int"])
  assert_eq(index.definitions[1].references, ["Int"])
  assert_eq(index.definitions[2].references, ["@pkg.Foo", "@pkg.Bar"])
  assert_eq(index.definitions[5].references, ["@pkg.read"])
  assert_eq(index.definitions[8].references, ["Point", "Render"])
  assert_eq(index.definitions[13].references, ["Point::render", "Point"])
  assert_false(index.definitions[15].references.contains("State"))
  assert_eq(index.definitions[16].references, [
    "Point", "Point::render", "Point::debug",
  ])
}
