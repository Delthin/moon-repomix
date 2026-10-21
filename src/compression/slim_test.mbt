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
  let tables_source =
    #|const suggestions: Record<string, string[]> = { install: ['npm install', 'pnpm install'], build: ['npm run build'] };
    #|const inferredLarge = { a: 'alpha', b: 'beta', c: 'charlie', d: 'delta', e: 'echo', f: 'foxtrot', g: 'golf', h: 'hotel' };
    #|function readLarge(key: string) { return inferredLarge[key]; }
    #|const arrayLarge = { a: ['alpha'], b: ['beta'], c: ['charlie'], d: ['delta'], e: ['echo'], f: ['foxtrot'], g: ['golf'], h: ['hotel'] };
    #|function readArray(key: string) { return arrayLarge[key]; }
    #|const constructors: Record<string, Widget> = { a: new Widget('alpha'), b: new Widget('beta'), c: new Widget('charlie'), d: new Widget('delta'), e: new Widget('echo'), f: new Widget('foxtrot'), g: new Widget('golf'), h: new Widget('hotel') };
    #|class Widget { constructor(...constructors: string[]) { this.values = constructors; } }
    #|function widget(key: string) { return constructors[key]; }
    #|const outputSchema: Record<string, string> = { schemaKey: 'javascript', schemaOther: 'python' };
    #|export function getSchema(): Record<string, string> { return outputSchema; }
    #|const serialized: Record<string, string> = { serializedKey: 'javascript', serializedOther: 'python' };
    #|export function serialize() { return JSON.stringify(serialized); }
    #|const observed: Record<string, string> = { observedKey: 'javascript', observedOther: 'python' };
    #|export function keys() { return Object.keys(observed); }
    #|const nestedAssertion: Record<string, string[]> = { assertionKey: ['javascript'] as const, assertionOther: ['python'] };
    #|const largeLiteral = { literalKey: 'a', b: 'b', c: 'c', d: 'd', e: 'e', f: 'f', g: 'g', h: 'h' } as const;
    #|const largePublic = { publicLargeKey: 'a', b: 'b', c: 'c', d: 'd', e: 'e', f: 'f', g: 'g', h: 'h' };
    #|export { largePublic };
    #|const arrayAlias: Record<string, string[]> = { arrayAliasKey: ['alpha'], arrayAliasOther: ['beta'] };
    #|const alias = arrayAlias;
    #|const mutated: Record<string, string[]> = { mutatedKey: ['alpha'], mutatedOther: ['beta'] };
    #|mutated[key] = incoming;
    #|const updated: Record<string, number> = { updatedKey: 100, updatedOther: 200 };
    #|updated[key]++;
    #|const deleted: Record<string, number> = { deletedKey: 100, deletedOther: 200 };
    #|delete deleted[key];
    #|const augmented: Record<string, number> = { augmentedKey: 100, augmentedOther: 200 };
    #|augmented[key] += 1;
    #|const wrappedMutation: Record<string, string[]> = { wrappedMutationKey: ['alpha'], wrappedMutationOther: ['beta'] };
    #|(wrappedMutation[key]) = incoming;
    #|const destructuredMutation: Record<string, string[]> = { destructuredMutationKey: ['alpha'], destructuredMutationOther: ['beta'] };
    #|[destructuredMutation[key]] = incoming;
    #|let loopMutation: Record<string, string[]> = { loopMutationKey: ['alpha'], loopMutationOther: ['beta'] };
    #|for (loopMutation of items) { consume(loopMutation); }
    #|const queried: Record<string, string[]> = { queryKey: ['alpha'], queryOther: ['beta'] };
    #|type Element = typeof queried['queryKey'];
    #|const schemaConstructors: Record<string, Widget> = { constructorSchemaKey: new Widget({ handler: callback }), b: new Widget('b'), c: new Widget('c'), d: new Widget('d'), e: new Widget('e'), f: new Widget('f'), g: new Widget('g'), h: new Widget('h') };
    #|const calls: Record<string, Widget> = { callKey: new Widget(factory()), b: new Widget('b'), c: new Widget('c'), d: new Widget('d'), e: new Widget('e'), f: new Widget('f'), g: new Widget('g'), h: new Widget('h') };
    #|const computedArray: Record<string, string[]> = { ['computedArrayKey']: ['alpha'], computedArrayOther: ['beta'] };
    #|const spreadArray: Record<string, string[]> = { ...externalArrayMap, spreadArrayKey: ['alpha'] };
    #|const methodArray: Record<string, unknown> = { literalMethod(value: string): string { return value.repeat(100); }, methodArrayKey: ['alpha'] };
    #|const narrowArray: Record<string, 'literal'[]> = { narrowArrayKey: ['literal'], narrowArrayOther: ['literal'] };
    #|class Tagged { readonly kind = 'literal' as const; }
    #|const literalConstructors: Record<string, { readonly kind: 'literal' }> = { literalConstructorKey: new Tagged(), b: new Tagged(), c: new Tagged(), d: new Tagged(), e: new Tagged(), f: new Tagged(), g: new Tagged(), h: new Tagged() };
    #|const behaviorAlias: Record<string, Handler> = { behaviorAliasKey: handler, b: handler, c: handler, d: handler, e: handler, f: handler, g: handler, h: handler };
    #|const smallInferred = { smallKey: 'alpha', b: 'beta', c: 'charlie', d: 'delta', e: 'echo', f: 'foxtrot', g: 'golf' };
    #|const smallConstructors: Record<string, Widget> = { smallConstructorKey: new Widget('alpha'), b: new Widget('beta'), c: new Widget('charlie'), d: new Widget('delta'), e: new Widget('echo'), f: new Widget('foxtrot'), g: new Widget('golf') };
    #|export { remote } from './remote';
    #|export * from './types';
    #|
  let tables = @compression.compress("private-tables.ts", tables_source)
  assert_true(tables.applied)
  for
    fragment in [
      "const suggestions: Record<string, string[]> = /* … */;", "const inferredLarge = /* … */;",
      "const arrayLarge = /* … */;", "const constructors: Record<string, Widget> = /* … */;",
      "this.values = constructors;", "getSchema(): Record<string, string>", "schemaKey:",
      "schemaOther:", "serializedKey:", "serializedOther:", "observedKey:", "observedOther:",
      "assertionKey:", "assertionOther:", "literalKey:", "as const", "publicLargeKey:",
      "export { largePublic };", "arrayAliasKey:", "arrayAliasOther:", "const alias = arrayAlias;",
      "mutatedKey:", "mutatedOther:", "updatedKey:", "updatedOther:", "deletedKey:",
      "deletedOther:", "augmentedKey:", "augmentedOther:", "wrappedMutationKey:",
      "wrappedMutationOther:", "destructuredMutationKey:", "destructuredMutationOther:",
      "loopMutationKey:", "loopMutationOther:", "queryKey:", "queryOther:", "typeof queried['queryKey']",
      "constructorSchemaKey:", "callKey:", "['computedArrayKey']:", "computedArrayOther:",
      "...externalArrayMap", "spreadArrayKey:", "literalMethod(value: string): string",
      "methodArrayKey:", "narrowArrayKey:", "narrowArrayOther:", "literalConstructorKey:",
      "behaviorAliasKey: handler", "smallKey:", "smallConstructorKey:", "export { remote } from './remote';",
      "export * from './types';",
    ] {
    assert_true(tables.text.contains(fragment), msg=fragment[:])
  }
  assert_false(tables.text.contains("repeat(100)"))
  let shadow_source =
    #|const shadowed: Record<string, string[]> = { a: ['alpha'], b: ['beta'] };
    #|function readShadow(key: string) { return shadowed[key]; }
    #|function parameter(shadowed: unknown) { return shadowed; }
    #|function destructured({ shadowed }: Options) { return shadowed; }
    #|function localShadow() { const shadowed = input; return shadowed; }
    #|function loopShadow() { for (const shadowed of items) { consume(shadowed); } }
    #|function catchShadow() { try { work(); } catch (shadowed) { consume(shadowed); } }
    #|function hoistedShadow() { if (condition) { var shadowed = input; } consume(shadowed); }
    #|const blockFunction: Record<string, string[]> = { blockFunctionKey: ['alpha'], blockFunctionOther: ['beta'] };
    #|export function functionBoundary() { if (condition) { function blockFunction() {} } return blockFunction; }
    #|const blockClass: Record<string, string[]> = { blockClassKey: ['alpha'], blockClassOther: ['beta'] };
    #|export function classBoundary() { if (condition) { class blockClass {} } return blockClass; }
    #|const typeOnly: Record<string, string[]> = { typeOnlyKey: ['alpha'], typeOnlyOther: ['beta'] };
    #|export function typeBoundary() { type typeOnly = string; return typeOnly; }
    #|const signatureDefault: Record<string, string[]> = { signatureDefaultKey: ['alpha'], signatureDefaultOther: ['beta'] };
    #|export function signatureBoundary(value = signatureDefault) { var signatureDefault = local; return value; }
    #|namespace builtinShadow {
    #|  type Record<K, V> = { localTypeKey: V };
    #|  const protectedMap: Record<string, string[]> = { builtinShadowKey: ['alpha'], builtinShadowOther: ['beta'] };
    #|  export function read(key: string) { return protectedMap[key]; }
    #|}
    #|
  let shadow = @compression.compress("shadow-tables.ts", shadow_source)
  assert_true(shadow.applied)
  assert_true(
    shadow.text.contains(
      "const shadowed: Record<string, string[]> = /* … */;",
    ),
    msg=shadow.text[:],
  )
  assert_true(shadow.text.contains("builtinShadowKey:"))
  assert_true(shadow.text.contains("builtinShadowOther:"))
  for
    key in [
      "blockFunctionKey:", "blockFunctionOther:", "blockClassKey:", "blockClassOther:",
      "typeOnlyKey:", "typeOnlyOther:", "signatureDefaultKey:", "signatureDefaultOther:",
    ] {
    assert_true(shadow.text.contains(key), msg=key[:])
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
