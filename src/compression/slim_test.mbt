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
    #|const suggestions: Record<string, string[]> = { install: ['npm install', 'pnpm install'], build: ['npm run build'] };
    #|const inferredLarge = { a: 'alpha', b: 'beta', c: 'charlie', d: 'delta', e: 'echo', f: 'foxtrot', g: 'golf', h: 'hotel' };
    #|function readLarge(key: string) { return inferredLarge[key]; }
    #|const constructors: Record<string, Widget> = { a: new Widget('alpha'), b: new Widget('beta'), c: new Widget('charlie'), d: new Widget('delta'), e: new Widget('echo'), f: new Widget('foxtrot'), g: new Widget('golf'), h: new Widget('hotel') };
    #|class Widget { constructor(...constructors: string[]) { this.values = constructors; } }
    #|function widget(key: string) { return constructors[key]; }
    #|const outputSchema: Record<string, string> = { schemaKey: 'javascript', schemaOther: 'python' };
    #|export function getSchema() { return outputSchema; }
    #|const serialized: Record<string, string> = { serializedKey: 'javascript', serializedOther: 'python' };
    #|export function serialize() { return JSON.stringify(serialized); }
    #|const observed: Record<string, string> = { observedKey: 'javascript', observedOther: 'python' };
    #|export function keys() { return Object.keys(observed); }
    #|const nestedAssertion: Record<string, string[]> = { assertionKey: ['javascript'] as const, assertionOther: ['python'] };
    #|const largeLiteral = { literalKey: 'a', b: 'b', c: 'c', d: 'd', e: 'e', f: 'f', g: 'g', h: 'h' } as const;
    #|const largePublic = { publicLargeKey: 'a', b: 'b', c: 'c', d: 'd', e: 'e', f: 'f', g: 'g', h: 'h' };
    #|export { largePublic };
    #|const mutated: Record<string, string[]> = { mutatedKey: ['alpha'], mutatedOther: ['beta'] };
    #|mutated[key] = incoming;
    #|const queried: Record<string, string[]> = { queryKey: ['alpha'], queryOther: ['beta'] };
    #|type Element = typeof queried['queryKey'];
    #|const schemaConstructors: Record<string, Widget> = { constructorSchemaKey: new Widget({ handler: callback }), b: new Widget('b'), c: new Widget('c'), d: new Widget('d'), e: new Widget('e'), f: new Widget('f'), g: new Widget('g'), h: new Widget('h') };
    #|export { remote } from './remote';
    #|export * from './types';
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
  for
    fragment in [
      "const suggestions: Record<string, string[]> = /* … */;", "const inferredLarge = /* … */;",
      "const constructors: Record<string, Widget> = /* … */;", "this.values = constructors;",
      "schemaKey:", "schemaOther:", "serializedKey:", "serializedOther:", "observedKey:",
      "observedOther:", "assertionKey:", "as const", "literalKey:", "publicLargeKey:",
      "export { largePublic };", "mutatedKey:", "mutatedOther:", "queryKey:", "queryOther:",
      "typeof queried['queryKey']", "constructorSchemaKey:", "export { remote } from './remote';",
      "export * from './types';",
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
    #|function Instance(value) { this.value = value; this.enabled = true; }
    #|Instance.prototype.enabled = true;
    #|Instance['prototype'].alias = helper;
    #|function unknownTarget(target, value) { target[key] = value; }
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
      "function normalize(value)", "this.value = value;", "this.enabled = true;",
      "Instance.prototype.enabled = true;", "Instance['prototype'].alias = helper;",
      "target[key] = value;",
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
  let data_source =
    #|import type { File } from './file';
    #|interface Dependency { name: string; version?: string; }
    #|interface Stack { packageManager?: string; dependencies: Dependency[]; }
    #|export function metrics(input: string[], key: string): { filePaths: string[]; counts: Record<string, number> } {
    #|  const counts: Record<string, number> = {};
    #|  for (const path of input) { counts[path] = input.length; }
    #|  for (const path of input) { counts[path] = key.length; }
    #|  return { filePaths: input, counts };
    #|}
    #|export function output(files: File[]): { files: Record<string, string>; version: number } {
    #|  const document = { files: files.reduce((acc, file) => { acc[file.path] = file.content; return acc; }, {} as Record<string, string>), version: 1 };
    #|  return JSON.stringify(document);
    #|}
    #|export function stack(key: string, parsed: Stack): Stack {
    #|  const results = new Map<string, Stack>();
    #|  const result = results.get(key);
    #|  if (parsed.packageManager) { result.packageManager = parsed.packageManager; }
    #|  function nested(result: any) { result.packageManager = helper; }
    #|  return result;
    #|}
    #|function shadow(key: string) {
    #|  const counts: Record<string, number> = {};
    #|  function parameter(counts: any) { counts[key] = helper; }
    #|  function destructured({ counts }: any) { counts[key] = helper; }
    #|  for (const counts of targets) { counts[key] = helper; }
    #|  for (let counts = target; keep; step()) { counts[key] = helper; }
    #|  counts[key] = input.length;
    #|}
    #|interface API { run: (value: string) => string; }
    #|function install(key: string) { const api: API = target; api[key] = helper; }
    #|function unknown(key: string) { const result = factory(); result[key] = helper; }
    #|function hoisted(key: string) {
    #|  const counts: Record<string, number> = {};
    #|  function inner() { counts[key] = helper; if (condition) { var counts = target; } }
    #|}
    #|function aliases(method: string) {
    #|  const dependency = require('./nested-dependency');
    #|  const handler = dependency.handler;
    #|  const handlerAlias = handler;
    #|  const api = externalApp;
    #|  api[method] = handlerAlias;
    #|}
    #|interface WithBehavior { packageManager: string; install(): void; }
    #|function behavior(key: string) { const obj: WithBehavior = target; obj[key] = helper; }
    #|interface Inherited extends External { packageManager: string; }
    #|function inherited(key: string) { const obj: Inherited = target; obj[key] = helper; }
    #|interface Merged { value: string; }
    #|interface Merged { install(): void; }
    #|function merged(key: string) { const obj: Merged = target; obj[key] = helper; }
    #|interface LaterPublic { value: string; }
    #|export { LaterPublic };
    #|function laterAugmented(key: string) { const obj: LaterPublic = target; obj[key] = helper; }
    #|export interface Public { value: string; }
    #|function augmented(key: string) { const obj: Public = target; obj[key] = helper; }
    #|function aliasedSchema(files: File[]) {
    #|  const documentAlias = { files: files.reduce((acc, file) => { acc[file.path] = file.content; return acc; }, {} as Record<string, string>), config: { enabled: true } };
    #|  const configAlias = documentAlias.config;
    #|  const secondAlias = configAlias;
    #|  return JSON.stringify(secondAlias);
    #|}
    #|function literalSchema() { const localLiteral = { literalMode: 'text', choices: ['a', 'b'] } as const; return localLiteral; }
    #|function installedSchema() { const localSchema = { schemaField: 'configuration' }; app.schema = localSchema; }
    #|function config(input: Config): Config {
    #|  const output = { output: (() => { const mergedOutput = { ...input.output, mode: 'text' }; mergedOutput.filePath = desiredPath; return mergedOutput; })() };
    #|  return validate(output);
    #|}
    #|
  let data = @compression.compress("data.ts", data_source)
  assert_true(data.applied)
  for
    fragment in [
      "import type { File } from './file';", "metrics(input: string[], key: string): { filePaths: string[]; counts: Record<string, number> }",
      "output(files: File[]): { files: Record<string, string>; version: number }",
      "const counts: Record<string, number> = {};", "const document = { files: /* … */, version: 1 };",
      "function nested(result: any)", "result.packageManager = helper;", "function parameter(counts: any)",
      "function destructured({ counts }: any)", "for (const counts of targets)",
      "let counts = target; keep; step()", "counts[key] = helper;", "api[key] = helper;",
      "result[key] = helper;", "function inner() { counts[key] = helper;", "const dependency = require('./nested-dependency');",
      "const handler = dependency.handler;", "const handlerAlias = handler;", "const api = externalApp;",
      "api[method] = handlerAlias;", "const obj: WithBehavior = target; obj[key] = helper;",
      "const obj: Inherited = target; obj[key] = helper;", "interface Inherited extends External",
      "const obj: Merged = target; obj[key] = helper;", "const obj: Public = target; obj[key] = helper;",
      "const obj: LaterPublic = target; obj[key] = helper;", "const documentAlias = { files: /* … */, config: { enabled: true } };",
      "const configAlias = documentAlias.config;", "const secondAlias = configAlias;",
      "const localLiteral = { literalMode: 'text', choices: ['a', 'b'] } as const;",
      "const localSchema = { schemaField:", "app.schema = localSchema;", "const output = { output: (() =>",
      "const mergedOutput = { ...input.output, mode: 'text' };", "mergedOutput.filePath = desiredPath;",
    ] {
    assert_true(data.text.contains(fragment))
  }
  for
    fragment in [
      "for (const path", "counts[path]", "counts[key] = input.length", "reduce(",
      "acc[file.path]", "result.packageManager = parsed.packageManager", "if (parsed.packageManager)",
    ] {
    assert_false(data.text.contains(fragment))
  }
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
