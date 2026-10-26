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
static size_t allocation_no, fail_at, live, live_bytes, peak_bytes;
static struct { void *pointer; size_t size; } tracked[64];
static int should_fail(void) { return ++allocation_no == fail_at; }
static size_t tracked_index(void *p) {
  for (size_t i = 0; i < 64; ++i) if (tracked[i].pointer == p) return i;
  abort();
}
static void track_new(void *p, size_t n) {
  if (!p) return;
  size_t i = tracked_index(NULL);
  tracked[i].pointer = p; tracked[i].size = n;
  ++live; live_bytes += n;
  if (live_bytes > peak_bytes) peak_bytes = live_bytes;
}
static void *test_malloc(size_t n) {
  if (should_fail()) return NULL;
  void *p = malloc(n); track_new(p, n); return p;
}
static void *test_calloc(size_t n, size_t size) {
  if (should_fail()) return NULL;
  assert(!n || size <= SIZE_MAX / n);
  void *p = calloc(n, size); track_new(p, n * size); return p;
}
static void *test_realloc(void *p, size_t n) {
  if (should_fail()) return NULL;
  assert(n);
  if (!p) { void *out = realloc(NULL, n); track_new(out, n); return out; }
  size_t i = tracked_index(p);
  void *out = realloc(p, n);
  if (out) {
    live_bytes -= tracked[i].size; live_bytes += n;
    tracked[i].pointer = out; tracked[i].size = n;
    if (live_bytes > peak_bytes) peak_bytes = live_bytes;
  }
  return out;
}
static void test_free(void *p) {
  if (!p) return;
  size_t i = tracked_index(p); assert(live);
  --live; live_bytes -= tracked[i].size;
  tracked[i].pointer = NULL; tracked[i].size = 0;
  free(p);
}
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
static void reset(size_t fail) {
  allocation_no = 0; fail_at = fail; peak_bytes = live_bytes;
}
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
static void clock_tests(void) {
  // A tiny full clock forces wraparound probe clusters and real deletion on
  // every insertion. Same-hash keys differ by NUL contents and length.
  NtMemoEntry entries[8] = {0}; uint8_t payload[4 * NT_MEMO_KEY];
  NtMemo m = {.entries = entries, .payload = payload, .slots = 8,
              .key_limit = 4, .payload_capacity = sizeof(payload), .replacing = 1};
  const uint8_t keys[4][3] = {{'a',0,'b'}, {'a',0,'c'}, {'a',0,0}, {'b',0,'a'}};
  for (size_t i = 0; i < 4; ++i) nt_memo_put(&m, keys[i], i == 2 ? 2 : 3, 7, (int32_t)i);
  assert(m.keys == 4 && m.used == sizeof(payload));
  assert(nt_memo_get(&m, keys[0], 3, 7) == 0);
  assert(nt_memo_get(&m, keys[2], 2, 7) == 2);
  assert(nt_memo_get(&m, keys[2], 3, 7) == -1);
  for (size_t i = 0; i < 8; ++i) entries[i].recent = 0;
  assert(nt_memo_get(&m, keys[0], 3, 7) == 0); // second chance protects slot 7
  m.hand = 7;
  uint8_t incoming[] = {'n',0,'w'};
  nt_memo_put(&m, incoming, 3, 7, 9);
  incoming[1] = '!'; // borrowed source is never retained or aliased
  const uint8_t original[] = {'n',0,'w'};
  assert(nt_memo_get(&m, incoming, 3, 7) == -1);
  assert(nt_memo_get(&m, original, 3, 7) == 9);
  assert(nt_memo_get(&m, keys[0], 3, 7) == 0);
  assert(nt_memo_get(&m, keys[1], 3, 7) == -1);
  assert(nt_memo_get(&m, keys[2], 2, 7) == 2);
  assert(nt_memo_get(&m, keys[3], 3, 7) == 3);
  uint8_t too_long[257] = {0}; size_t hand = m.hand;
  nt_memo_put(&m, too_long, sizeof(too_long), 7, 99);
  assert(m.hand == hand && m.keys == 4 && m.used == sizeof(payload));
  for (uint32_t round = 0; round < 4096; ++round) {
    struct { uint8_t key[8]; size_t n; uint64_t h; int32_t count; } previous[4];
    size_t found = 0;
    for (size_t i = 0; i < 8; ++i) if (entries[i].len) {
      NtMemoEntry e = entries[i]; assert(found < 4 && e.len <= 8);
      previous[found].n = e.len; previous[found].h = e.hash;
      previous[found].count = (int32_t)e.count;
      memcpy(previous[found++].key, payload + e.offset, e.len);
    }
    assert(found == 4);
    uint8_t key[] = {'x', 0, (uint8_t)(round >> 8), (uint8_t)round, 'z', 0};
    uint64_t h = round % 3 ? 7 : nt_hash(key, sizeof(key));
    nt_memo_put(&m, key, sizeof(key), h, (int32_t)round + 100);
    assert(nt_memo_get(&m, key, sizeof(key), h) == (int32_t)round + 100);
    memset(key, 0xff, sizeof(key));
    size_t survivors = 0;
    for (size_t i = 0; i < 4; ++i) {
      int32_t got = nt_memo_get(&m, previous[i].key, previous[i].n, previous[i].h);
      assert(got == -1 || got == previous[i].count);
      survivors += got >= 0;
    }
    assert(survivors == 3); // exactly the selected victim, no broken probe chain
    unsigned occupied = 0, cells = 0;
    for (size_t i = 0; i < 8; ++i) if (entries[i].len) {
      size_t cell = entries[i].offset / NT_MEMO_KEY;
      assert(entries[i].offset % NT_MEMO_KEY == 0 && cell < 4);
      assert(!(cells & (1u << cell))); cells |= 1u << cell; ++occupied;
    }
    assert(occupied == 4 && cells == 15 && m.keys == 4 && m.used == sizeof(payload));
  }
  assert(live == 0 && live_bytes == 0);
  puts("clock: 4096 evictions, second chance, wrapped mixed/full-hash collisions, NUL/length, source mutation, unique fixed cells and exact survivor counts passed");
}
static void assert_scanner(const NtCounter *c, const uint8_t *s, size_t n) {
  for (size_t start = 0; start < n;) {
    size_t expected = nt_piece_end_general(c, s, n, start);
    assert(expected > start && expected <= n);
    assert(nt_piece_end(c, s, n, start) == expected);
    start = expected;
  }
}
static void scanner_tests(const NtCounter *c) {
  const char *words[] = {"a", "A", "ABC", "abc", "ABCdef", "abCD", "ABcdEFgh"};
  const char *edges[] = {"", "'s", "'S", "'RE", "'vE", "'lL", "'r", "'r\xc3\xa9",
    "'\xc5\xbf", "\xc3\xa9", "\xc4\xb0", "\xc7\x85", "\xca\xb0", "\xe7\x8c\xab",
    "\xcc\x81", "\xe0\xa4\x83", "\xe0\xb8\xb1", "\xd9\xa1", "\xc2\xb2",
    "\xf0\x90\x90\xa8", "\xf0\x9f\x98\x80", "\xe2\x80\xa8", "\xe2\x80\x8d"};
  uint8_t text[128];
  for (unsigned prefix = 0; prefix < 128; ++prefix)
    for (size_t w = 0; w < sizeof(words) / sizeof(words[0]); ++w)
      for (size_t e = 0; e < sizeof(edges) / sizeof(edges[0]); ++e) {
        size_t wn = strlen(words[w]), en = strlen(edges[e]);
        text[0] = (uint8_t)prefix; memcpy(text + 1, words[w], wn);
        memcpy(text + 1 + wn, edges[e], en); memcpy(text + 1 + wn + en, "aB!", 3);
        assert_scanner(c, text, 1 + wn + en + 3);
        assert_scanner(c, text + 1, wn + en); // exact ends, not just padded input
      }
  // Exhaustive short ASCII strings cover priority, prefix, CR/LF, numbers,
  // contractions and end bounds; every original boundary must remain identical.
  const uint8_t alphabet[] = {'a','A','b','B',' ',0,'\r','\n','\t','\'','s','1','!','/'};
  for (size_t sample = 0; sample < 38416; ++sample) { // 14^4
    size_t code = sample;
    for (size_t j = 0; j < 4; ++j) { text[j] = alphabet[code % 14]; code /= 14; }
    for (size_t n = 1; n <= 4; ++n) assert_scanner(c, text, n);
  }
  assert(nt_ascii_letter_end((const uint8_t *)" ABCdef", 7, 0) == 7);
  assert(nt_ascii_letter_end((const uint8_t *)"aB", 2, 0) == 1);
  assert(nt_ascii_letter_end((const uint8_t *)"a'\xc5\xbf", 4, 0) == 4);
  assert(nt_ascii_letter_end((const uint8_t *)"A\xcc\x81", 3, 0) == 0);
  puts("scanner: all 128 ASCII prefixes x 7 case patterns x 23 Unicode/contraction edges and 14^4 short ASCII strings match unchanged general scanner");
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
  assert(nt_rank_hashed(&c, aa, 2, nt_hash(aa, 2)) == 0);
  assert(nt_rank_hashed(&c, aab, 3, nt_hash(aab, 3)) == 1);
  NtScratch scratch = {0};
  assert(nt_bpe(&c, (const uint8_t *)"aaaab", 5, &scratch) == 2);
  assert(slow_bpe(&c, (const uint8_t *)"aaaab", 5) == 2);
  test_free(scratch.nodes); free(c.slots);
  assert(live == 0);
  puts("BPE: independent left-tie/rank-zero regression passed");
}
static void session_tests(const NtCounter *c) {
  size_t baseline = live, baseline_bytes = live_bytes;
  reset(1); assert(!nt_session_new());
  assert(nt_session_count(NULL, c, NULL, 0) == -1);
  nt_session_free(NULL); assert(live == baseline);
  uint8_t text[7305];
  memcpy(text, "hi ", 3);
  memset(text + 3, 'a', 300); text[303] = ' ';
  memset(text + 304, 'b', 1000); text[1304] = ' ';
  memset(text + 1305, '!', 6000);
  reset(0); int32_t expected = nt_counter_count(c, text, sizeof(text));
  assert(expected > 0 && live == baseline);
  // All five lazy per-session allocations: two optional memo blocks and three
  // scratch growth steps. A later call must work after every failure point.
  for (size_t failure = 1; failure <= 5; ++failure) {
    reset(0); NtSession *s = nt_session_new(); assert(s);
    reset(failure);
    int32_t got = nt_session_count(s, c, text, sizeof(text));
    assert(got == (failure <= 2 ? expected : -1));
    assert(s->scratch.size == 0);
    if (failure <= 2) assert(s->memo.attempted && !s->memo.entries);
    reset(0);
    assert(nt_session_count(s, c, text, sizeof(text)) == expected);
    if (failure <= 2) assert(allocation_no == 0); // no memo allocation retry
    assert(nt_session_count(s, c, NULL, 0) == 0);
    assert(nt_session_count(s, c, (uint8_t *)"hello", 5) == 1);
    assert(nt_session_count(s, c, text, sizeof(text)) == expected);
    assert(nt_session_count(s, NULL, text, sizeof(text)) == -1);
    assert(nt_session_count(s, c, text, (size_t)INT32_MAX + 1) == -1);
    assert(s->scratch.size == 0);
    assert(nt_session_count(s, c, text, sizeof(text)) == expected);
    nt_session_free(s); assert(live == baseline && live_bytes == baseline_bytes);
  }
  reset(0); NtSession *s = nt_session_new(); assert(s);
  assert(nt_session_count(s, c, NULL, 0) == 0);
  assert(nt_session_count(s, c, (uint8_t *)"!", 1) == 1);
  assert(allocation_no == 1 && !s->memo.attempted && !s->scratch.nodes);
  uint8_t *borrowed = malloc(5); assert(borrowed); memcpy(borrowed, "hello", 5);
  assert(nt_session_count(s, c, borrowed, 5) == 1);
  free(borrowed); // cached full key must survive release of the input snapshot
  assert(s->memo.payload_capacity == NT_MEMO_PAYLOAD && s->memo.key_limit == NT_MEMO_KEYS);
  reset(0);
  assert(nt_session_count(s, c, (uint8_t *)"hello", 5) == 1);
  assert(allocation_no == 0);
  NtSession *other = nt_session_new(); assert(other && !other->memo.attempted);
  size_t old_keys = s->memo.keys;
  assert(nt_session_count(other, c, text, sizeof(text)) == expected);
  assert(s->memo.keys == old_keys && !s->scratch.nodes && other->scratch.nodes);
  assert(nt_session_count(s, c, text, sizeof(text)) == expected);
  assert(s->scratch.nodes != other->scratch.nodes && s->memo.payload != other->memo.payload);
  nt_session_free(other);
  // Exercise the true 24 MiB live scratch bound, including replacement growth.
  uint8_t *large = malloc(NT_MAX_PIECE + 1); assert(large);
  memset(large, 1, NT_MAX_PIECE + 1);
  reset(0);
  assert(nt_session_count(s, c, large, NT_MAX_PIECE / 2) == (int32_t)(NT_MAX_PIECE / 2));
  assert(nt_session_count(s, c, large, NT_MAX_PIECE) == (int32_t)NT_MAX_PIECE);
  size_t bound = baseline_bytes + sizeof(NtSession) + NT_MEMO_PAYLOAD +
                 NT_MEMO_SLOTS * sizeof(NtMemoEntry) + NT_MAX_PIECE * 24;
  assert(live_bytes <= bound && peak_bytes <= bound);
  assert(s->scratch.capacity == NT_MAX_PIECE);
  assert(nt_session_count(s, c, large, NT_MAX_PIECE + 1) == -1);
  assert(s->scratch.size == 0);
  assert(nt_session_count(s, c, (uint8_t *)"hello", 5) == 1);
  assert(nt_session_count(s, c, NULL, 0) == 0);
  free(large); nt_session_free(s);
  assert(live == baseline && live_bytes == baseline_bytes);
  // 8192 distinct complete 256-byte letter pieces across separate documents,
  // then reverse-order lookups after saturation and a noncached late document.
  reset(0); s = nt_session_new(); assert(s);
  int32_t counts[NT_MEMO_KEYS]; uint8_t key[256];
  key[0] = ' '; memset(key + 1, 'a', 252);
  for (size_t i = 0; i < NT_MEMO_KEYS; ++i) {
    key[253] = (uint8_t)('a' + i / 676);
    key[254] = (uint8_t)('a' + i / 26 % 26);
    key[255] = (uint8_t)('a' + i % 26);
    counts[i] = nt_session_count(s, c, key, sizeof(key)); assert(counts[i] > 0);
  }
  assert(s->memo.keys == NT_MEMO_KEYS && s->memo.used == NT_MEMO_PAYLOAD);
  reset(0);
  for (size_t i = NT_MEMO_KEYS; i-- > 0;) {
    key[253] = (uint8_t)('a' + i / 676);
    key[254] = (uint8_t)('a' + i / 26 % 26);
    key[255] = (uint8_t)('a' + i % 26);
    assert(nt_session_count(s, c, key, sizeof(key)) == counts[i]);
    assert(nt_memo_get(&s->memo, key, sizeof(key), nt_hash(key, sizeof(key))) == counts[i]);
  }
  assert(nt_session_count(s, c, text, sizeof(text)) == expected);
  assert(nt_session_count(s, c, (uint8_t *)"hello", 5) == 1);
  assert(nt_session_count(s, c, NULL, 0) == 0);
  assert(s->memo.keys == NT_MEMO_KEYS && s->memo.used == NT_MEMO_PAYLOAD);
  // Two later file vocabularies replace all first keys without growing payload.
  // The last file's pieces must now hit instead of being excluded forever.
  NtSession *isolated = nt_session_new(); assert(isolated);
  assert(nt_session_count(isolated, c, (const uint8_t *)"hello", 5) == 1);
  assert(isolated->memo.keys == 1 && isolated->memo.payload != s->memo.payload);
  for (size_t epoch = 0; epoch < 2; ++epoch) {
    uint8_t recent_key[] = " clockaaa";
    for (size_t i = 0; i < NT_MEMO_KEYS; ++i) {
      size_t id = epoch * NT_MEMO_KEYS + i;
      recent_key[6] = (uint8_t)('a' + id / 676);
      recent_key[7] = (uint8_t)('a' + id / 26 % 26);
      recent_key[8] = (uint8_t)('a' + id % 26);
      int32_t exact = nt_counter_count(c, recent_key, 9);
      size_t before_allocation = allocation_no;
      assert(nt_session_count(s, c, recent_key, 9) == exact);
      assert(allocation_no == before_allocation); // eviction/insertion allocate nothing
      assert(nt_memo_get(&s->memo, recent_key, 9, nt_hash(recent_key, 9)) == exact);
      memset(recent_key + 6, '!', 3); // source overwritten before next call
    }
    reset(0);
    for (size_t i = NT_MEMO_KEYS - 128; i < NT_MEMO_KEYS; ++i) {
      size_t id = epoch * NT_MEMO_KEYS + i;
      recent_key[6] = (uint8_t)('a' + id / 676);
      recent_key[7] = (uint8_t)('a' + id / 26 % 26);
      recent_key[8] = (uint8_t)('a' + id % 26);
      int32_t cached = nt_memo_get(&s->memo, recent_key, 9, nt_hash(recent_key, 9));
      assert(cached > 0 && nt_session_count(s, c, recent_key, 9) == cached);
    }
    assert(allocation_no == 0);
    assert(s->memo.keys == NT_MEMO_KEYS && s->memo.used == NT_MEMO_PAYLOAD);
    assert(s->memo.payload_capacity == NT_MEMO_PAYLOAD && s->memo.slots == NT_MEMO_SLOTS);
    assert(isolated->memo.keys == 1);
    assert(nt_memo_get(&isolated->memo, (const uint8_t *)"hello", 5,
                       nt_hash((const uint8_t *)"hello", 5)) == 1);
    assert(nt_session_count(isolated, c, (const uint8_t *)"hello", 5) == 1);
    assert(allocation_no == 0);
  }
  nt_session_free(isolated);
  nt_session_free(s); assert(live == baseline && live_bytes == baseline_bytes);
  puts("session: lazy bounded memo/scratch, owned cross-document keys, independent sessions, saturation, every OOM recovery, heap reset and 24MiB transient bound passed");
}
int main(void) {
  size_t rn, un;
  uint8_t *r = read_bytes("assets/tokenizer-o200k_base.tiktoken", &rn);
  uint8_t *u = read_bytes("assets/tokenizer-unicode-16.0.0.txt", &un);
  memo_tests(); clock_tests(); synthetic_tie();
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
  scanner_tests(c);
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
  session_tests(c);
  assert(before == (nt_hash(c->arena, c->offsets[NT_RANKS]) ^
                    nt_hash(c->categories, NT_CATEGORY_BYTES) ^
                    nt_hash((uint8_t *)c->slots, NT_SLOTS * sizeof(uint32_t))));
  nt_counter_free(c); assert(live == 0 && live_bytes == 0);
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
  for (size_t i = 0; i < 16; ++i) {
    moonbit_bytes_t rb = moonbit_make_bytes_raw((int32_t)rn), ub = moonbit_make_bytes_raw((int32_t)un);
    memcpy(rb, r, rn); memcpy(ub, u, un);
    NtHandle *owner = moon_repomix_counter_new(rb, ub); assert(owner->counter);
    moonbit_decref(rb); moonbit_decref(ub);
    reset(1);
    NtSessionHandle *failed = moon_repomix_count_session_new(); assert(!failed->session);
    moonbit_bytes_t input = moonbit_make_bytes_raw(5); memcpy(input, "hello", 5);
    assert(moon_repomix_count_session_count(failed, owner, input) == -1);
    moonbit_decref(failed);
    reset(0);
    NtSessionHandle *session = moon_repomix_count_session_new(); assert(session->session);
    moonbit_incref(session);
    for (size_t call = 0; call < 8; ++call) {
      assert(moon_repomix_count_session_count(session, owner, input) == 1);
      moonbit_decref(input);
      input = moonbit_make_bytes_raw(5); memcpy(input, "hello", 5);
    }
    moonbit_decref(input); moonbit_decref(session);
    if (i % 2) {
      moonbit_decref(owner); // finalizer must not access the already freed owner
      moonbit_decref(session);
    } else {
      moonbit_decref(session);
      moonbit_decref(owner);
    }
    assert(live == 0 && live_bytes == 0);
  }
  puts("session FFI: 16 real lifecycles, fresh/released input per call, constructor OOM, refcounts and both finalizer orders passed");
  moonbit_bytes_t empty = moonbit_make_bytes_raw(0);
  NtHandle *unavailable = moon_repomix_counter_new(empty, empty);
  assert(moon_repomix_counter_count(unavailable, empty) == -1);
  moonbit_decref(unavailable); moonbit_decref(empty); assert(live == 0);
  free(r); free(u);
  puts("FFI: 16 real external-object lifecycles, early resource release, repeated borrowed calls, finalizer and null handle passed");
  puts("PASS: ASan/UBSan kernel+FFI; all tracked C allocations released (live=0)");
  return 0;
}
