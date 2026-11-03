/* Synthetic, standalone C ownership/quota regression. No MoonBit runtime. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../vendor/runtime/lib/include/tree_sitter/api.h"
static unsigned live_buffers, live_cursors, live_parsers, live_trees;
static unsigned allocations, fail_at;
static void *index_realloc(void *, size_t);
static void index_free(void *);
static TSTreeCursor cursor_new(TSNode);
static void cursor_delete(TSTreeCursor *);
static TSParser *parser_new(void);
static void parser_delete(TSParser *);
static TSTree *parse_string(TSParser *, const TSTree *, const char *, uint32_t);
static void tree_delete(TSTree *);
#define realloc index_realloc
#define free index_free
#define ts_tree_cursor_new cursor_new
#define ts_tree_cursor_delete cursor_delete
#define ts_parser_new parser_new
#define ts_parser_delete parser_delete
#define ts_parser_parse_string parse_string
#define ts_tree_delete tree_delete
#include "../definition_core.c"
#undef realloc
#undef free
#undef ts_tree_cursor_new
#undef ts_tree_cursor_delete
#undef ts_parser_new
#undef ts_parser_delete
#undef ts_parser_parse_string
#undef ts_tree_delete

static void *index_realloc(void *p, size_t n) {
  if (++allocations == fail_at) return NULL;
  int fresh = p == NULL;
  void *out = realloc(p, n);
  if (out && fresh) ++live_buffers;
  return out;
}
static void index_free(void *p) {
  if (p) { assert(live_buffers); --live_buffers; }
  free(p);
}
static TSTreeCursor cursor_new(TSNode node) {
  ++live_cursors;
  return ts_tree_cursor_new(node);
}
static void cursor_delete(TSTreeCursor *cursor) {
  assert(live_cursors--);
  ts_tree_cursor_delete(cursor);
}
static TSParser *parser_new(void) {
  TSParser *parser = ts_parser_new();
  if (parser) ++live_parsers;
  return parser;
}
static void parser_delete(TSParser *parser) {
  assert(live_parsers--);
  ts_parser_delete(parser);
}
static TSTree *parse_string(TSParser *parser, const TSTree *old, const char *text, uint32_t n) {
  TSTree *tree = ts_parser_parse_string(parser, old, text, n);
  if (tree) ++live_trees;
  return tree;
}
static void tree_delete(TSTree *tree) {
  assert(live_trees--);
  ts_tree_delete(tree);
}
static uint32_t word(const uint8_t *p) {
  return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static void released(void) {
  assert(!live_buffers && !live_cursors && !live_parsers && !live_trees);
}
static void drop(SDIndex result, int status, unsigned definitions) {
  assert(result.status == status);
  if (status) assert(!result.wire && !result.length);
  else {
    assert(result.wire && result.length >= 8);
    assert(word(result.wire) == 0 && word(result.wire + 4) == definitions);
    uint32_t at = 8;
    for (unsigned i = 0; i < definitions; ++i) {
      assert(at + 28 <= result.length);
      assert(word(result.wire + at + 4) >= word(result.wire + at));
      assert(word(result.wire + at + 8) >= 1);
      assert(word(result.wire + at + 12) >= word(result.wire + at + 8));
      uint32_t name = word(result.wire + at + 16);
      uint32_t qualified_name = word(result.wire + at + 20);
      uint32_t refs = word(result.wire + at + 24);
      assert(name && qualified_name && refs <= SD_MAX_REFS);
      at += 28 + name + qualified_name;
      assert(at <= result.length);
      for (unsigned r = 0; r < refs; ++r) {
        assert(at + 4 <= result.length);
        uint32_t length = word(result.wire + at);
        at += 4 + length;
        assert(at <= result.length);
      }
    }
    assert(at == result.length); /* No hidden/truncated records. */
  }
  index_free(result.wire);
  released();
}
static SDIndex run(int language, const char *text) {
  return sd_index(language, text, (uint32_t)strlen(text), 0);
}
static char *repeat(const char *prefix, const char *piece, unsigned n, const char *suffix) {
  size_t a = strlen(prefix), b = strlen(piece), c = strlen(suffix);
  char *text = malloc(a + b * n + c + 1);
  assert(text);
  memcpy(text, prefix, a);
  for (unsigned i = 0; i < n; ++i) memcpy(text + a + i * b, piece, b);
  memcpy(text + a + b * n, suffix, c + 1);
  return text;
}
static char *ref_function(unsigned refs, unsigned functions, int moonbit) {
  char one[8192];
  size_t at = (size_t)sprintf(one, "%s", moonbit ? "fn use_refs() { sink(" : "function use_refs() { return sink(");
  for (unsigned i = 1; i < refs; ++i)
    at += (size_t)sprintf(one + at, "%sr%u", i == 1 ? "" : ",", i);
  strcpy(one + at, moonbit ? ") }\n" : "); }\n");
  return repeat("", one, functions, "");
}
int main(void) {
  drop(run(0, "const LIMIT = 7;\nres.render = function(view) { return helper(view, LIMIT); };"), 0, 2);
  drop(run(1, "export const LIMIT = 1; export function f(): number { return LIMIT; }"), 0, 2);
  drop(run(2, "export const View = () => <Panel>{LIMIT}</Panel>;"), 0, 1);
  drop(run(3, "消息 = '😀'\r\n@decorate(消息)\r\ndef read(arg):\r\n    return use(arg, 消息)\r\n"), 0, 2);
  drop(run(0, "const OK = 1; function bad( {"), 1, 0);
  drop(run(3, "OK = 1\ndef bad(:\n  pass"), 1, 0);
  drop(run(4, ""), 0, 0);
  drop(run(4, "const LIMIT = 7\nfn read() -> Int { LIMIT }\n"), 0, 2);
  drop(run(4, "trait Read { read(Self) -> Int }\nimpl Read for Int with read(self) { self }\n"), 0, 3);
  drop(run(4, "pub fn Int::read(Self) -> Int\nimpl Read for Int\n"), 0, 2);
  drop(run(4, "const OK = 1\nfn broken( {"), 1, 0);
  drop(run(4, "let 消息 = \"😀\"\r\nfn 读取() -> String { 消息 }\r\n"), 0, 2);
  drop(run(4, "pub typealias @pkg.(Foo as Local, Bar)\npub extend Point with Render::{render, debug}\nfn Point::render(self : Point) -> Int { self.x }\nextenum @pkg.State += { Extra }\n"), 0, 6);
  drop(run(4, "fn outer() { if true { fn inner() { 1 }; inner() } }"), 0, 1);
  drop(run(5, ""), 6, 0);
  drop(sd_index(0, "", SD_MAX_INPUT + 1, 0), 3, 0);
  char *input = repeat("", " ", SD_MAX_INPUT, "");
  drop(sd_index(0, input, SD_MAX_INPUT, 0), 0, 0);
  free(input);
  char *defs = repeat("", "const same = 0;\n", SD_MAX_DEFINITIONS, "");
  drop(run(0, defs), 0, SD_MAX_DEFINITIONS);
  free(defs);
  defs = repeat("", "const same = 0;\n", SD_MAX_DEFINITIONS + 1, "");
  drop(run(0, defs), 3, 0);
  free(defs);
  char *refs = ref_function(SD_MAX_REFS, 1, 0);
  drop(run(0, refs), 0, 1);
  free(refs);
  refs = ref_function(SD_MAX_REFS + 1, 1, 0);
  drop(run(0, refs), 3, 0);
  free(refs);
  refs = ref_function(SD_MAX_REFS, SD_MAX_TOTAL_REFS / SD_MAX_REFS, 0);
  drop(run(0, refs), 0, SD_MAX_TOTAL_REFS / SD_MAX_REFS);
  free(refs);
  refs = ref_function(SD_MAX_REFS, SD_MAX_TOTAL_REFS / SD_MAX_REFS + 1, 0);
  drop(run(0, refs), 3, 0);
  free(refs);
  char *nodes = repeat("", "0;", SD_MAX_NODES / 3 + 1, "");
  drop(run(0, nodes), 3, 0);
  /* A deterministic tiny parser budget, not a flaky duration assertion. */
  drop(sd_index(0, nodes, (uint32_t)strlen(nodes), 1), 2, 0);
  free(nodes);
  char *visits = repeat("const a=0", ",a=0", 1000, ";");
  drop(run(0, visits), 3, 0);
  free(visits);
  char *long_name = repeat("const ", "a", SD_MAX_NAME + 1, " = 0;");
  drop(run(0, long_name), 3, 0);
  free(long_name);
  char *open = repeat("const deep = ", "[", SD_MAX_DEPTH + 1, "0");
  char *deep = repeat(open, "]", SD_MAX_DEPTH + 1, ";");
  free(open);
  drop(run(0, deep), 3, 0);
  free(deep);
  defs = repeat("", "fn same() { 0 }\n", SD_MAX_DEFINITIONS, "");
  drop(run(4, defs), 0, SD_MAX_DEFINITIONS);
  drop(sd_index(4, defs, (uint32_t)strlen(defs), 1), 2, 0);
  free(defs);
  defs = repeat("", "fn same() { 0 }\n", SD_MAX_DEFINITIONS + 1, "");
  drop(run(4, defs), 3, 0);
  free(defs);
  refs = ref_function(SD_MAX_REFS, 1, 1);
  drop(run(4, refs), 0, 1);
  free(refs);
  refs = ref_function(SD_MAX_REFS + 1, 1, 1);
  drop(run(4, refs), 3, 0);
  free(refs);
  open = repeat("fn deep() { ", "[", SD_MAX_DEPTH + 1, "0");
  deep = repeat(open, "]", SD_MAX_DEPTH + 1, " }");
  free(open);
  drop(run(4, deep), 3, 0);
  free(deep);
  open = repeat("fn ", "A", 3000, "::");
  long_name = repeat(open, "m", 2000, "() { 0 }");
  free(open);
  drop(run(4, long_name), 3, 0);
  free(long_name);
  const char *ref_prefix[] = {"function use() { return ", "def use():\n    return ", "fn use() { "};
  const char *ref_suffix[] = {"; }", "\n", " }"};
  const int ref_languages[] = {0, 3, 4};
  for (unsigned i = 0; i < 3; ++i) {
    long_name = repeat(ref_prefix[i], "m", SD_MAX_NAME, ref_suffix[i]);
    drop(run(ref_languages[i], long_name), 0, 1);
    free(long_name);
    long_name = repeat(ref_prefix[i], "m", SD_MAX_NAME + 1, ref_suffix[i]);
    drop(run(ref_languages[i], long_name), 3, 0);
    free(long_name);
  }
  assert(inclusive_end((TSPoint){0, 0}, (TSPoint){3, 0}) == 3);
  assert(inclusive_end((TSPoint){0, 0}, (TSPoint){3, 1}) == 4);
  assert(inclusive_end((TSPoint){0, 0}, (TSPoint){0, 0}) == 1);
  Indexer limits = {0};
  assert(visit(&limits, SD_MAX_DEPTH));
  assert(!visit(&limits, SD_MAX_DEPTH + 1) && limits.result.status == 3);
  limits = (Indexer){.visits = SD_MAX_VISITS - 1};
  assert(visit(&limits, 0));
  assert(!visit(&limits, 0) && limits.result.status == 3);
  limits = (Indexer){0};
  assert(!reserve(&limits, SD_MAX_WIRE + 1) && limits.result.status == 3);
  released();
  /* Exercise MoonBit-only cursor/name paths under every wire growth failure. */
  for (unsigned pass = 0; pass < 2; ++pass) {
    int language = pass ? 4 : 0;
    char *growth = repeat("", pass ?
      "trait Read { read(Self) -> Int }\nimpl Read for Int with read(self) { self }\n" :
      "const same = 0;\n", 200, "");
    unsigned definitions = pass ? 600 : 200;
    allocations = 0;
    drop(run(language, growth), 0, definitions);
    unsigned growths = allocations;
    assert(growths > 1);
    for (unsigned i = 1; i <= growths; ++i) {
      allocations = 0;
      fail_at = i;
      drop(run(language, growth), 3, 0);
    }
    fail_at = 0;
    free(growth);
  }
  released();
  puts("definition core: grammar, wire, exact quotas, timeout, allocation-failure cleanup passed");
  return 0;
}
