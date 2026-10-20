///|
test "private scalar tables fold but public keys and literal types survive" {
  let source =
    #|// Syntax highlighting language lookup.
    #|const languages: Record<string, string> = {
    #|  // Internal categories
    #|  js: 'javascript',
    #|  py: 'python',
    #|};
    #|export function lookup(extension: string) { return languages[extension]; }
    #|const flags: Record<number, boolean> = { 1: true, 2: false };
    #|export const publicMap: Record<string, string> = { publicKey: 'javascript', otherKey: 'python' };
    #|const laterExport: Record<string, string> = { laterKey: 'javascript', nextKey: 'python' };
    #|export { laterExport };
    #|const typedKeys: Record<string, string> = { typedKey: 'javascript', typedOther: 'python' };
    #|export type Key = keyof typeof typedKeys;
    #|export const literals = { mode: 'long-literal-type-value', other: 'another-literal-type' } as const;
    #|export type Mode = typeof literals.mode;
    #|const inferred = { inferredKey: 'javascript', inferredOther: 'python' };
    #|const narrow: Record<'left' | 'right', string> = { left: 'javascript', right: 'python' };
    #|const behavior: Record<string, unknown> = { run(value) { return value.repeat(100); }, alias: inferred };
    #|const computed: Record<string, string> = { ['computedKey']: 'javascript', computedOther: 'python' };
    #|const spread: Record<string, string> = { ...inferred, spreadKey: 'javascript' };
    #|const defaultMap: Record<string, string> = { defaultKey: 'javascript', defaultOther: 'python' };
    #|const aliasMap: Record<string, string> = { aliasKey: 'javascript', aliasOther: 'python' };
    #|const exportedAlias = aliasMap;
    #|export { exportedAlias };
    #|export default { defaultMap };
    #|export interface Options { value: 'long-public-type-value' }
    #|export enum Language { JS = 'javascript', PY = 'python' }
    #|
  let out = @compression.compress("tables.ts", source)
  assert_true(out.applied)
  assert_true(
    out.text.contains(
      "// Syntax highlighting language lookup.\nconst languages: Record<string, string> = /* … */;",
    ),
  )
  assert_false(out.text.contains("Internal categories"))
  assert_false(out.text.contains("js:"))
  assert_true(
    out.text.contains("const flags: Record<number, boolean> = /* … */;"),
  )
  for
    fragment in [
      "lookup(extension: string)", "publicKey:", "otherKey:", "laterKey:", "nextKey:",
      "export { laterExport }", "['computedKey']:", "computedOther:", "...inferred",
      "spreadKey:", "defaultKey:", "defaultOther:", "export default { defaultMap }",
      "aliasKey:", "aliasOther:", "const exportedAlias = aliasMap;", "export { exportedAlias };",
      "typedKey:", "typedOther:", "keyof typeof typedKeys", "inferredKey:", "inferredOther:",
      "left:", "right:", "run(value)", "alias: inferred", "mode: 'long-literal-type-value'",
      "other: 'another-literal-type'", "as const", "export type Mode = typeof literals.mode",
      "value: 'long-public-type-value'", "JS = 'javascript'", "PY = 'python'",
    ] {
    assert_true(out.text.contains(fragment))
  }
  assert_false(out.text.contains("repeat(100)"))
  assert_true(out.ranges.contains({ start_line: 1, end_line: 2, }))
  for range in out.ranges {
    assert_false(range.start_line <= 4 && range.end_line >= 4)
  }
}

///|
test "CommonJS exports aliases and callback-installed member APIs keep signatures" {
  let source =
    #|const dependency = require('./long-dependency-path');
    #|module.exports = require('./lib/express');
    #|module.exports = exports = createApplication;
    #|exports.application = applicationPrototype;
    #|exports.named = veryLongHelperIdentifier;
    #|exports.options = { enabled: true, handler(value) { return value.repeat(100); } };
    #|module . exports.config = { visible: true };
    #|module['exports'].flag = true;
    #|function createApplication() {
    #|  var app = function(req, res, next) { app.handle(req, res, next); };
    #|  app.get = function(name) { return this.settings[name] + 'implementation details'; };
    #|  app.route = veryLongRouteHelper;
    #|  return app;
    #|}
    #|module.exports = function exported(req, res) {
    #|  function nested(value) { return value.repeat(100); }
    #|  return nested(req.url);
    #|};
    #|methods.forEach(function(method) {
    #|  app[method] = function(path) {
    #|    function normalize(value) { return value.repeat(100); }
    #|    return normalize(path);
    #|  };
    #|});
    #|items.forEach(function(item) { console.log(item, 'implementation details'); });
    #|console.log('unrelated implementation details');
    #|
  let out = @compression.compress("express.cjs", source)
  assert_true(out.applied)
  for
    fragment in [
      "const dependency = require('./long-dependency-path');", "module.exports = require('./lib/express');",
      "module.exports = exports = createApplication;", "exports.application = applicationPrototype;",
      "exports.named = veryLongHelperIdentifier;", "exports.options = { enabled: true, handler(value)",
      "module . exports.config = { visible: true };", "module['exports'].flag = true;",
      "function createApplication()", "var app = function(req, res, next)", "app.get = function(name)",
      "app.route = veryLongRouteHelper;", "module.exports = function exported(req, res)",
      "function nested(value)", "methods.forEach(function(method)", "app[method] = function(path)",
      "function normalize(value)",
    ] {
    assert_true(out.text.contains(fragment))
  }
  for
    fragment in [
      "repeat(100)", "app.handle(", "implementation details", "items.forEach", "console.log",
      "return normalize(",
    ] {
    assert_false(out.text.contains(fragment))
  }
  let table = @compression.compress(
    "export-table.ts", "const map: Record<string, string> = { commonKey: 'javascript', commonOther: 'python' };\nmodule.exports = map;\nfunction helper() { return 'long implementation details'; }\n",
  )
  assert_true(table.applied)
  assert_true(table.text.contains("commonKey:"))
  assert_true(table.text.contains("commonOther:"))
  assert_true(table.text.contains("module.exports = map;"))
}

///|
test "omission gaps merge and AST whitespace compacts without rewriting raw literals" {
  let source =
    #|export function first() {
    #|  work('first implementation details');
    #|
    #|  work('second implementation details');
    #|}
    #|
    #|
    #|/** Keep comment
    #|
    #|exactly. */
    #|export const raw = `first
    #|
    #|
    #|last` as const;
    #|
    #|
    #|export function second() {
    #|  work('third implementation details');
    #|}
    #|
  let expected =
    #|export function first() {
    #|  /* … */
    #|}
    #|/** Keep comment
    #|
    #|exactly. */
    #|export const raw = `first
    #|
    #|
    #|last` as const;
    #|export function second() {
    #|  /* … */
    #|}
    #|
  for
    (input, output) in [
      (source, expected),
      (
        source.replace_all(old="\n", new="\r\n"),
        expected.replace_all(old="\n", new="\r\n"),
      ),
    ] {
    let out = @compression.compress("gaps.ts", input)
    assert_true(out.applied)
    assert_eq(out.text, output)
    assert_eq(out.ranges, [
      { start_line: 1, end_line: 1, },
      { start_line: 5, end_line: 5, },
      { start_line: 8, end_line: 14, },
      { start_line: 17, end_line: 17, },
      { start_line: 19, end_line: 19, },
    ])
  }
}
