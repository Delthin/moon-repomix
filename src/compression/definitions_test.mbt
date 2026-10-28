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
  for path in ["file.rs", "file.mbt", "file.go", "file.java", "file.txt"] {
    let index = @compression.index_definitions(path, "function okay() {}")
    assert_eq(index.reason, Some("unsupported-language"))
    assert_eq(index.definitions, [])
  }
  for
    (path, source) in [
      ("bad.js", "const OK = 1; function broken( {"),
      ("bad.ts", "export function bad(x: ) {}"),
      ("bad.py", "OK = 1\ndef bad(:\n  pass"),
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
