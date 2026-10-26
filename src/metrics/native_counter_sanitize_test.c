// Standalone sanitizer unit harness, not linked into the product.
// Compile the unmodified product kernel and FFI with a system-allocator copy
// of the MoonBit runtime. Fault injection wraps only the kernel allocations.
#include <assert.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>
static size_t allocation_no, fail_at, live;
static int should_fail(void) { return ++allocation_no == fail_at; }
static void *test_malloc(size_t n) {
  if (should_fail()) return NULL;
  void *p = malloc(n);
  if (p) ++live;
  return p;
}
static void *test_calloc(size_t n, size_t size) {
  if (should_fail()) return NULL;
  void *p = calloc(n, size);
  if (p) ++live;
  return p;
}
static void *test_realloc(void *p, size_t n) {
  if (should_fail()) return NULL;
  void *out = realloc(p, n);
  if (out && !p) ++live;
  return out;
}
static void test_free(void *p) { if (p) { assert(live); --live; free(p); } }
#define malloc test_malloc
#define calloc test_calloc
#define realloc test_realloc
#define free test_free
#include "native_counter.c"
#undef malloc
#undef calloc
#undef realloc
#undef free
#include "native_counter_ffi.c"
_Noreturn void moonbit_panic(void) { abort(); }
static void reset(size_t fail) { allocation_no = 0; fail_at = fail; }
static uint8_t *read_bytes(const char *path, size_t *n) {
  FILE *f = fopen(path, "rb"); assert(f);
  assert(fseek(f, 0, SEEK_END) == 0);
  long length = ftell(f); assert(length > 0);
  *n = (size_t)length;
  rewind(f);
  uint8_t *s = malloc(*n); assert(s);
  assert(fread(s, 1, *n, f) == *n); assert(!fclose(f));
  return s;
}
// Independent exhaustive adjacent-pair recomputation, no heap/linked nodes.
static int32_t slow_bpe(const NtCounter *c, const uint8_t *s, size_t n) {
  if (nt_rank(c, s, n) >= 0) return 1;
  size_t boundary[130]; assert(n < 130);
  for (size_t i = 0; i <= n; ++i) boundary[i] = i;
  size_t count = n;
  for (;;) {
    int32_t best = INT32_MAX;
    size_t left = count;
    for (size_t i = 0; i + 1 < count; ++i) {
      int32_t rank = nt_rank(c, s + boundary[i], boundary[i + 2] - boundary[i]);
      if (rank >= 0 && rank < best) { best = rank; left = i; }
    }
    if (left == count) return (int32_t)count;
    for (size_t i = left + 1; i < count; ++i) boundary[i] = boundary[i + 1];
    --count;
  }
}
static void memo_tests(void) {
  NtMemo m = {0}; reset(0); nt_memo_init(&m, SIZE_MAX);
  assert(m.entries && m.payload && m.slots == NT_MEMO_SLOTS);
  const uint8_t a[] = {'a', 0, 'b'}, b[] = {'a', 0, 'c'};
  nt_memo_put(&m, a, sizeof(a), 123, 7);
  assert(nt_memo_get(&m, b, sizeof(b), 123) == -1);
  nt_memo_put(&m, b, sizeof(b), 123, 9);
  assert(nt_memo_get(&m, a, sizeof(a), 123) == 7);
  assert(nt_memo_get(&m, b, sizeof(b), 123) == 9);
  assert(nt_memo_get(&m, a, 2, 123) == -1);
  uint8_t too_long[257] = {0};
  nt_memo_put(&m, too_long, sizeof(too_long), 123, 11);
  assert(m.keys == 2 && m.used == 6);
  test_free(m.entries); test_free(m.payload);
  m = (NtMemo){0}; nt_memo_init(&m, SIZE_MAX);
  uint8_t key[257]; memset(key, 'x', sizeof(key));
  for (uint32_t i = 0; i < NT_MEMO_KEYS; ++i) {
    memcpy(key, &i, sizeof(i));
    nt_memo_put(&m, key, 256, nt_hash(key, 256), (int32_t)i + 1);
  }
  assert(m.keys == NT_MEMO_KEYS && m.used == NT_MEMO_PAYLOAD);
  for (uint32_t i = 0; i < NT_MEMO_KEYS; i += 17) {
    memcpy(key, &i, sizeof(i));
    assert(nt_memo_get(&m, key, 256, nt_hash(key, 256)) == (int32_t)i + 1);
  }
  uint32_t extra = NT_MEMO_KEYS; memcpy(key, &extra, sizeof(extra));
  nt_memo_put(&m, key, 256, nt_hash(key, 256), 10);
  nt_memo_put(&m, key, 257, 123, 10);
  assert(m.keys == NT_MEMO_KEYS && m.used == NT_MEMO_PAYLOAD);
  assert(nt_memo_get(&m, key, 256, nt_hash(key, 256)) == -1);
  test_free(m.entries); test_free(m.payload);
  assert(live == 0);
  puts("memo: exact NUL/collisions, 8192 keys, 2MiB payload, 256/257-byte boundary passed");
}
static void synthetic_tie(void) {
  // aa is rank zero: in aaaab the left tie produces aa|aab (2), whereas
  // a middle-first tie strands a|aa|a|b (4). Never treat zero as miss.
  NtCounter c = {0};
  uint8_t arena[] = {'a','a','a','a','b'};
  uint32_t offsets[] = {0,2,5};
  c.arena = arena; c.offsets = offsets; c.max_token = 3;
  c.slots = calloc(NT_SLOTS, sizeof(uint32_t)); assert(c.slots);
  const uint8_t aa[] = {'a','a'}, aab[] = {'a','a','b'};
  c.slots[nt_hash(aa, 2) & (NT_SLOTS - 1)] = 1;
  uint32_t slot = (uint32_t)nt_hash(aab, 3) & (NT_SLOTS - 1);
  while (c.slots[slot]) slot = (slot + 1) & (NT_SLOTS - 1);
  c.slots[slot] = 2;
  assert(nt_rank(&c, aa, 2) == 0);
  NtScratch scratch = {0};
  assert(nt_bpe(&c, (const uint8_t *)"aaaab", 5, &scratch) == 2);
  assert(slow_bpe(&c, (const uint8_t *)"aaaab", 5) == 2);
  test_free(scratch.nodes); free(c.slots);
  assert(live == 0);
  puts("BPE: independent left-tie/rank-zero regression passed");
}
int main(void) {
  size_t rn, un;
  uint8_t *r = read_bytes("assets/tokenizer-o200k_base.tiktoken", &rn);
  uint8_t *u = read_bytes("assets/tokenizer-unicode-16.0.0.txt", &un);
  memo_tests(); synthetic_tie();
  reset(0);
  assert(!nt_array(SIZE_MAX, 2, 0));
  assert(!nt_counter_new(r, SIZE_MAX, u, un));
  assert(!nt_counter_new(r, rn, u, SIZE_MAX));
  assert(!nt_counter_new(NULL, rn, u, un));
  assert(nt_counter_count(NULL, NULL, 0) == -1);
  for (size_t failure = 1; failure <= 6; ++failure) {
    reset(failure);
    NtCounter *c = nt_counter_new(r, rn, u, un);
    if (failure <= 5) assert(!c);
    else { assert(c); assert(nt_counter_count(c, (uint8_t *)"hello", 5) == 1); }
    nt_counter_free(c); assert(live == 0);
  }
  puts("constructor: all 5 allocation failures and optional arena shrink failure clean");
  reset(0);
  for (size_t n = 0; n < 32; ++n) {
    assert(!nt_counter_new(r, n, u, un)); assert(live == 0);
  }
  NtCounter *c = nt_counter_new(r, rn, u, un); assert(c);
  size_t immutable_live = live;
  assert(nt_counter_count(c, NULL, 0) == 0);
  assert(nt_counter_count(c, r, (size_t)INT32_MAX + 1) == -1);
  uint64_t before = nt_hash(c->arena, c->offsets[NT_RANKS]) ^
                    nt_hash(c->categories, NT_CATEGORY_BYTES) ^
                    nt_hash((uint8_t *)c->slots, NT_SLOTS * sizeof(uint32_t));
  NtScratch scratch = {0}; uint32_t seed = 12345;
  const char *alphabet = "aaaaababcd def!?0123';ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  for (size_t sample = 0; sample < 4096; ++sample) {
    uint8_t text[96]; size_t n = 2 + sample % 94;
    for (size_t j = 0; j < n; ++j) {
      seed = seed * 1664525u + 1013904223u;
      text[j] = sample % 7 ? (uint8_t)alphabet[(seed >> 16) % strlen(alphabet)] : (uint8_t)(seed >> 24);
    }
    assert(nt_bpe(c, text, n, &scratch) == slow_bpe(c, text, n));
  }
  test_free(scratch.nodes); assert(live == immutable_live);
  puts("BPE: 4096 deterministic byte-piece differentials against exhaustive recomputation passed");
  // Valid UTF8 widths, NUL, long whitespace/punctuation, memo reuse and growth.
  uint8_t *text = malloc(12000); assert(text);
  memcpy(text, "hi ", 3);
  memset(text + 3, 'a', 300); text[303] = ' ';
  memset(text + 304, 'b', 1000); text[1304] = ' ';
  memset(text + 1305, '!', 6000);
  reset(0); int32_t expected = nt_counter_count(c, text, 7305); assert(expected > 0);
  size_t allocations = allocation_no; assert(allocations == 5);
  for (size_t failure = 1; failure <= allocations; ++failure) {
    reset(failure); int32_t got = nt_counter_count(c, text, 7305);
    assert(got == expected || got == -1);
    if (failure <= 2) assert(got == expected); // optional memo must remain exact
    else assert(got == -1); // scratch failure must request fallback
    assert(live == immutable_live);
  }
  reset(0);
  for (size_t i = 0; i < 64; ++i) {
    assert(nt_counter_count(c, text, 7305) == expected); assert(live == immutable_live);
  }
  memset(text, ' ', 4096); assert(nt_counter_count(c, text, 4096) > 0);
  const uint8_t utf8[] = {0,0x7f,0xc2,0x80,0xdf,0xbf,0xe0,0xa0,0x80,0xed,0x9f,0xbf,0xee,0x80,0x80,0xef,0xbb,0xbf,0xef,0xbf,0xbe,0xef,0xbf,0xbf,0xf0,0x90,0x80,0x80,0xf4,0x8f,0xbf,0xbf};
  assert(nt_counter_count(c, utf8, sizeof(utf8)) > 0);
  // Safe private probes even on truncated leading bytes and invalid positions.
  const uint8_t truncated[] = {0xf0,0x90,0x80};
  assert(nt_counter_piece_end(c, truncated, 3, 0) > 0);
  assert(nt_counter_piece_end(c, utf8, sizeof(utf8), -1) == -1);
  assert(nt_counter_piece_end(c, utf8, sizeof(utf8), (int32_t)sizeof(utf8)) == -1);
  uint8_t *large = malloc(NT_MAX_PIECE + 1); assert(large);
  memset(large, 1, NT_MAX_PIECE + 1);
  assert(nt_counter_count(c, large, NT_MAX_PIECE) == (int32_t)NT_MAX_PIECE);
  assert(nt_counter_count(c, large, NT_MAX_PIECE + 1) == -1);
  free(large); free(text);
  assert(before == (nt_hash(c->arena, c->offsets[NT_RANKS]) ^
                    nt_hash(c->categories, NT_CATEGORY_BYTES) ^
                    nt_hash((uint8_t *)c->slots, NT_SLOTS * sizeof(uint32_t))));
  nt_counter_free(c); assert(live == 0);
  puts("count: all 5 call allocation failures, scratch cap/growth/reuse, immutable table fingerprints passed");
  for (size_t i = 0; i < 16; ++i) {
    moonbit_bytes_t rb = moonbit_make_bytes_raw((int32_t)rn), ub = moonbit_make_bytes_raw((int32_t)un);
    memcpy(rb, r, rn); memcpy(ub, u, un);
    NtHandle *handle = moon_repomix_counter_new(rb, ub); assert(handle->counter);
    // Release both resource snapshots BEFORE the next call (no retained borrow).
    moonbit_decref(rb); moonbit_decref(ub);
    moonbit_bytes_t input = moonbit_make_bytes_raw(5); memcpy(input, "hello", 5);
    moonbit_incref(handle);
    for (size_t call = 0; call < 8; ++call) assert(moon_repomix_counter_count(handle, input) == 1);
    moonbit_decref(handle); assert(live > 0);
    moonbit_decref(input); moonbit_decref(handle); assert(live == 0);
  }
  moonbit_bytes_t empty = moonbit_make_bytes_raw(0);
  NtHandle *unavailable = moon_repomix_counter_new(empty, empty);
  assert(moon_repomix_counter_count(unavailable, empty) == -1);
  moonbit_decref(unavailable); moonbit_decref(empty); assert(live == 0);
  free(r); free(u);
  puts("FFI: 16 real external-object lifecycles, early resource release, repeated borrowed calls, finalizer and null handle passed");
  puts("PASS: ASan/UBSan kernel+FFI; all tracked C allocations released (live=0)");
  return 0;
}
