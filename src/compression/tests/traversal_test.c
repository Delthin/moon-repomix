/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE.
 * Synthetic white-box traversal tests. No MoonBit runtime is linked.
 * Define SC_TRAVERSAL_REFERENCE and link a separately renamed original core
 * to compare complete plans against the pre-cursor implementation. */
#include "../compression_core.h"
#include "../vendor/runtime/lib/include/tree_sitter/api.h"
#include <assert.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Instrument only calls made by the included core, not runtime internals.
 * The cancellation hook is deterministic, thread-local and test-only. */
static _Thread_local unsigned cursors, peak_cursors, steps, cancel_at;
static _Thread_local atomic_bool *cancel_hook;
static TSTreeCursor tracked_new(TSNode);
static void tracked_delete(TSTreeCursor *);
static TSNode tracked_current(const TSTreeCursor *);
#define ts_tree_cursor_new tracked_new
#define ts_tree_cursor_delete tracked_delete
#define ts_tree_cursor_current_node tracked_current
#include "../compression_core.c"
#undef ts_tree_cursor_new
#undef ts_tree_cursor_delete
#undef ts_tree_cursor_current_node

static TSTreeCursor tracked_new(TSNode node) {
  ++cursors;
  if (cursors > peak_cursors) peak_cursors = cursors;
  return ts_tree_cursor_new(node);
}
static void tracked_delete(TSTreeCursor *cursor) {
  assert(cursors);
  --cursors;
  ts_tree_cursor_delete(cursor);
}
static TSNode tracked_current(const TSTreeCursor *cursor) {
  if (++steps == cancel_at && cancel_hook) atomic_store(cancel_hook, true);
  return ts_tree_cursor_current_node(cursor);
}

#ifdef SC_TRAVERSAL_REFERENCE
SCPlan sc_reference_plan(int32_t, const char *, uint32_t, uint64_t);
#endif

static const TSLanguage *grammar(int language) {
  switch (language) {
    case 0: return tree_sitter_javascript();
    case 1: return tree_sitter_typescript();
    case 2: return tree_sitter_tsx();
    case 3: return tree_sitter_python();
    case 4: return tree_sitter_moonbit();
    case 5: return tree_sitter_go();
    case 6: return tree_sitter_rust();
    case 7: return tree_sitter_java();
    default: abort();
  }
}
static TSTree *parse(int language, const char *source) {
  TSParser *p = ts_parser_new();
  assert(p && ts_parser_set_language(p, grammar(language)));
  TSTree *tree = ts_parser_parse_string(p, NULL, source, (uint32_t)strlen(source));
  assert(tree && !ts_node_has_error(ts_tree_root_node(tree)));
  ts_parser_delete(p);
  return tree;
}
static void equal_node(TSNode a, TSNode b) {
  assert(a.id == b.id && a.tree == b.tree);
  assert(!memcmp(a.context, b.context, sizeof(a.context)));
  assert(!strcmp(ts_node_type(a), ts_node_type(b)));
  assert(ts_node_is_named(a) == ts_node_is_named(b));
}
static unsigned alias_nodes, anonymous_nodes, extra_nodes;
static void enumerate(Selection *s, TSNode node) {
  for (int named = 0; named <= 1; ++named) {
    Children it = children(node, named);
    TSNode child;
    uint32_t n = named ? ts_node_named_child_count(node) : ts_node_child_count(node), i = 0;
    while (children_next(s, &it, &child)) {
      assert(i < n);
      TSNode expected = named ? ts_node_named_child(node, i) : ts_node_child(node, i);
      equal_node(child, expected);
      equal_node(ts_node_parent(child), ts_node_parent(expected));
      if (!named) {
        alias_nodes += child.context[3] != 0;
        anonymous_nodes += !ts_node_is_named(child);
        extra_nodes += ts_node_is_extra(child);
        enumerate(s, child);
      }
      ++i;
    }
    assert(i == n && !it.active);
    children_close(&it); /* explicitly idempotent */
  }
}
static void equal_plan(SCPlan actual, SCPlan expected, const char *label) {
  if (actual.status != expected.status || actual.length != expected.length ||
      (!actual.status && memcmp(actual.keep, expected.keep, actual.length))) {
    fprintf(stderr, "plan mismatch: %s, status %d vs %d\n", label, actual.status, expected.status);
    abort();
  }
  assert((actual.keep != NULL) == (actual.status == 0));
}
static void compare(int language, const char *source, int status, const char *label) {
  uint32_t n = (uint32_t)strlen(source);
  /* Disable the parser clock only for differential/AST tests so scheduling
   * cannot make the two parses disagree. Production still uses 200000 us;
   * existing package/worker tests exercise that unchanged budget. */
  SCPlan actual = sc_plan(language, source, n, 0);
  if (actual.status != status)
    fprintf(stderr, "unexpected status: language %d %s, %d vs %d\n", language, label, actual.status, status);
  assert(actual.status == status && cursors == 0);
#ifdef SC_TRAVERSAL_REFERENCE
  SCPlan expected = sc_reference_plan(language, source, n, 0);
  equal_plan(actual, expected, label);
  free(expected.keep);
#else
  (void)label;
#endif
  atomic_bool cancel = false;
  SCPlan asynchronous = sc_plan_cancelable(language, source, n, 0, &cancel);
  equal_plan(asynchronous, actual, label);
  assert(cursors == 0);
  free(actual.keep); free(asynchronous.keep);
}
static const char *fixtures[] = {
  "// café 😀\r\nimport {x as renamed} from 'p';\r\n"
  "const table = {a:1,b:2,c:3,d:4,e:5,f:6,g:7,h:8};\r\n"
  "export function read(k) { let v=table[k]; if(v) { function nested() { return 123456789; } } return v; }\r\n"
  "module.exports.api = (x) => { const local = { run() { return 123456789; } }; return local; };\r\n",
  "// API\ninterface Read<T> { read(v: T): string; }\ntype Shape = {key: string};\n"
  "const table: Record<string, number[]> = {a:[1,2],b:[3,4]};\n"
  "export function read(key: string): number[] { return table[key]; }\n"
  "function shadow(table: string[]) { return table[0]; }\n"
  "const schema = {field: 'one', nested: {value: true}} as const;\n"
  "export type Keys = keyof typeof schema;\n",
  "// view\nexport function View() { const fn = () => { return 123456789; }; "
  "return <section title={'literal { }'}><span>{fn()}</span><div>text</div></section>; }\n",
  "# café 😀\r\nfrom package import name as alias\r\n"
  "@decorator\r\nclass Api:\r\n    \"\"\"docs\"\"\"\r\n    def read(self, value: int) -> int:\r\n"
  "        # implementation comment\r\n        \"\"\"method docs\"\"\"\r\n"
  "        if value:\r\n            def nested(arg):\r\n                return arg + 123456789\r\n"
  "        return value + 987654321\r\n",
  "///| 文档 😀\r\npub(all) struct Point { x : Int; y : Int } derive(Eq)\r\n"
  "pub fn f(value : Int, callback~ : (Int) -> Int = fn(x) { x + 789 }) -> Int {\r\n"
  "  fn nested(x : Int) -> Int { x + 123456789 }\r\n"
  "  if value > 0 { fn branch(x : Int) -> Int { x + 987654321 } }\r\n"
  "  callback(value)\r\n}\r\nextern \"js\" fn inline_call(x : Int) -> Int =\r\n"
  "  #| (x) => x + 123456789\r\n",
  "package p\nimport alias \"fmt\"\n// API\ntype Point struct { X, Y int }\n"
  "func F(x int) int { if x > 0 { type Local struct { Value int }; "
  "callback := func(v int) int { return v + 123456789 }; alias.Println(callback(x)) }; return x }\n",
  "// API\npub struct Point<T> { pub value: T }\npub fn f(x: i32) -> i32 {\n"
  " if x > 0 { fn nested(v: i32) -> i32 { v + 123456789 } }\n"
  " macro_rules! keep { () => { 123456789 } }\n keep!(); x\n}\n",
  "/** café 😀 */\r\nclass Api<T> {\r\n  int[] schema = {1,2,3};\r\n"
  "  static { initialize(); class Local { void run() { implementation(); } } }\r\n"
  "  <R extends T> R read(R value) throws Exception {\r\n"
  "    if (true) { class Nested { int get() { return 123456789; } } }\r\n"
  "    return new Runnable() { public void run() { implementation(); } };\r\n  }\r\n}\r\n",
};

typedef struct { char *text; size_t length, capacity; } Buffer;
static void append(Buffer *b, const char *format, ...) {
  va_list args; va_start(args, format);
  int n = vsnprintf(b->text + b->length, b->capacity - b->length, format, args);
  va_end(args);
  assert(n >= 0 && (size_t)n < b->capacity - b->length);
  b->length += (size_t)n;
}
static char *wide_source(int language) {
  const unsigned width = 384;
  Buffer b = {calloc(1, 160000), 0, 160000}; assert(b.text);
  switch (language) {
    case 0: case 1:
      append(&b, "const table%s = {", language ? ": Record<string, number[]>" : "");
      for (unsigned i = 0; i < width; ++i) append(&b, "%sk%u:[%u,%u]", i ? "," : "", i, i, i + 1);
      append(&b, "};\nexport function wide(key%s) {\n", language ? ": string" : "");
      for (unsigned i = 0; i < width; ++i) append(&b, " const value%u = 123456789;\n", i);
      append(&b, " function nested(x) { return x + 123456789; }\n return table[key];\n}\n");
      break;
    case 2:
      append(&b, "export function View() { return <section>");
      for (unsigned i = 0; i < width; ++i) append(&b, "<span data-k=\"%u\">literal { %u }</span>", i, i);
      append(&b, "</section>; }\n"); break;
    case 3:
      append(&b, "# API\nclass Wide:\n    def read(self, key):\n        \"\"\"docs\"\"\"\n");
      for (unsigned i = 0; i < width; ++i) append(&b, "        value%u = 123456789\n", i);
      append(&b, "        def nested(x):\n            return x + 123456789\n        return key\n"); break;
    case 4:
      append(&b, "pub(all) struct Wide {\n");
      for (unsigned i = 0; i < width; ++i) append(&b, "  field%u : Int\n", i);
      append(&b, "}\npub fn wide(x : Int) -> Int {\n");
      for (unsigned i = 0; i < width; ++i) append(&b, "  let value%u = 123456789\n", i);
      append(&b, "  fn nested(x : Int) -> Int { x + 123456789 }\n  x\n}\n"); break;
    case 5:
      append(&b, "package p\ntype Wide struct {\n");
      for (unsigned i = 0; i < width; ++i) append(&b, " Field%u int\n", i);
      append(&b, "}\nfunc WideFunc(x int) int {\n");
      for (unsigned i = 0; i < width; ++i) append(&b, " use(%u)\n", i);
      append(&b, " callback := func(x int) int { return x + 123456789 }; return callback(x)\n}\n"); break;
    case 6:
      append(&b, "pub struct Wide {\n");
      for (unsigned i = 0; i < width; ++i) append(&b, " pub field%u: i32,\n", i);
      append(&b, "}\npub fn wide(x: i32) -> i32 {\n");
      for (unsigned i = 0; i < width; ++i) append(&b, " let value%u = 123456789;\n", i);
      append(&b, " if x > 0 { fn nested(x: i32) -> i32 { x + 123456789 } } x\n}\n"); break;
    case 7:
      append(&b, "class Wide<T> {\n");
      for (unsigned i = 0; i < width; ++i) append(&b, " public int field%u = %u;\n", i, i);
      append(&b, " public int read(int x) {\n");
      for (unsigned i = 0; i < width; ++i) append(&b, " use(%u);\n", i);
      append(&b, " class Nested { int get() { return 123456789; } } return x;\n }\n}\n"); break;
    default: abort();
  }
  return b.text;
}
static void fixture_tests(void) {
  for (int language = 0; language < 8; ++language) {
    compare(language, fixtures[language], 0, "outline fixture");
    char *wide = wide_source(language);
    compare(language, wide, 0, "wide fixture");
    TSTree *tree = parse(language, wide);
    Selection s = {{NULL, (uint32_t)strlen(wide), 0}, language == 3, wide, NULL};
    enumerate(&s, ts_tree_root_node(tree));
    assert(!s.plan.status && !cursors);
    ts_tree_delete(tree); free(wide);
    tree = parse(language, fixtures[language]);
    s.source = fixtures[language]; s.plan.length = (uint32_t)strlen(s.source);
    enumerate(&s, ts_tree_root_node(tree));
    assert(!cursors);
    ts_tree_delete(tree);
    compare(language, "", 0, "empty");
    compare(language, "@%broken[", 1, "parse error");
  }
  assert(alias_nodes && anonymous_nodes && extra_nodes);
  /* False/early-return paths in scalar_value, opaque_value, scalar_table and
   * index_only, including aliases, constructor arguments and shadowed vars. */
  compare(1,
    "const table = {a:1,b:2,c:3,d:4,e:5,f:6,g:7,h:8};\n"
    "const alias = table;\n"
    "const spread = {a:1,...table};\n"
    "const computed = {[key]: 123456789, b: 1};\n"
    "const arrays: Record<string, number[]> = {a:[1,call()],b:[3,4]};\n"
    "const constructors: Record<string, Thing> = {a:new Thing({x:1}),b:new Thing(2),"
    "c:new Thing(3),d:new Thing(4),e:new Thing(5),f:new Thing(6),g:new Thing(7),h:new Thing(8)};\n"
    "function local(key) { if (key) { var table = {a:1}; } return table[key]; }\n",
    0, "private-table early returns");
}
static void depth_tests(void) {
  TSTree *tree = parse(0, "identifier;");
  TSNode leaf = ts_node_named_child(ts_node_named_child(ts_tree_root_node(tree), 0), 0);
  assert(is(leaf, "identifier"));
  for (unsigned depth = 512; depth <= 513; ++depth) {
    uint8_t keep[11]; memset(keep, 1, sizeof(keep));
    Selection s = {{keep, sizeof(keep), 0}, 0, "identifier;", NULL};
    comments(&s, leaf, depth); assert(s.plan.status == (depth > 512 ? 3 : 0));
    s.plan.status = 0;
    presentation(&s, leaf, depth); assert(s.plan.status == (depth > 512 ? 3 : 0));
    s.plan.status = 0;
    (void)contains_outline(&s, leaf, depth); assert(s.plan.status == (depth > 512 ? 3 : 0));
    s.plan.status = 0;
    (void)signature_binding(&s, leaf, depth); assert(s.plan.status == 0); /* original non-error cutoff */
    s.plan.status = 0;
    java_walk(&s, leaf, depth); assert(s.plan.status == (depth > 512 ? 3 : 0));
    s.plan.status = 0;
    moonbit_walk(&s, leaf, depth); assert(s.plan.status == (depth > 512 ? 3 : 0));
    assert(!cursors);
  }
  ts_tree_delete(tree);
  const unsigned depths[] = {64, 508, 509, 510, 511, 512, 513, 600};
  for (unsigned i = 0; i < sizeof(depths) / sizeof(*depths); ++i) {
    unsigned d = depths[i];
    char source[1300]; memset(source, '[', d); source[d] = '0';
    memset(source + d + 1, ']', d); source[d * 2 + 1] = ';'; source[d * 2 + 2] = 0;
    /* program -> statements(depth 1) -> contains_outline(expression, 2)
     * -> outer array(3) -> ... -> number(d + 3). That outline query reaches
     * the limit one level before the separate comments pass. */
    int expected = d + 3 > 512 ? 3 : 0;
    compare(1, source, expected, "nested array boundary");
  }
}
static void cancel_tests(void) {
  const unsigned points[] = {1, 2, 5, 17, 120, 1000};
  for (int language = 0; language < 8; ++language) {
    char *source = wide_source(language);
    for (unsigned i = 0; i < sizeof(points) / sizeof(*points); ++i) {
      atomic_bool cancel = false;
      steps = 0; cancel_at = points[i]; cancel_hook = &cancel;
      SCPlan plan = sc_plan_cancelable(language, source, (uint32_t)strlen(source), 0, &cancel);
      assert(atomic_load(&cancel) && plan.status == 5 && !plan.keep && !cursors);
      cancel_hook = NULL; cancel_at = 0;
    }
    atomic_bool cancel = true;
    SCPlan plan = sc_plan_cancelable(language, source, (uint32_t)strlen(source), 200000, &cancel);
    assert(plan.status == 5 && !plan.keep && !cursors);
    free(source);
  }
  assert(peak_cursors > 1);
}
static void *parallel(void *unused) {
  (void)unused;
  for (int language = 0; language < 8; ++language)
    compare(language, fixtures[language], 0, "parallel fixture");
  assert(!cursors);
  return NULL;
}
int main(void) {
  fixture_tests(); puts("PASS: all 8 grammars, wide/multilevel outlines, full plan differential, alias/named/anonymous/extra order");
  depth_tests(); puts("PASS: exact 512/513 guards, original signature cutoff, nested source boundaries");
  cancel_tests(); puts("PASS: deterministic mid-traversal cancellation and early-return cursor cleanup");
  pthread_t threads[4];
  for (int i = 0; i < 4; ++i) assert(!pthread_create(&threads[i], NULL, parallel, NULL));
  for (int i = 0; i < 4; ++i) assert(!pthread_join(threads[i], NULL));
  puts("PASS: four concurrent independent planners, no shared traversal state");
#ifdef SC_TRAVERSAL_REFERENCE
  puts("REFERENCE: original separately compiled indexed planner compared byte-for-byte");
#endif
  return 0;
}
