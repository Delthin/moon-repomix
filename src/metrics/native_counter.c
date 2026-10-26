// Original private C count implementation. The linked-symbol BPE algorithm is
// also used by bpe.mbt (adapted from tokenizers-moonbit 0.16.3, Apache-2.0;
// LICENSES/tokenizer-tokenizers-moonbit-Apache-2.0.txt). This implementation uses
// an indexed array min-heap, C-owned immutable ranks and call-local storage.
#include "native_counter.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define NT_RANKS 199998u
#define NT_SLOTS 524288u
#define NT_CATEGORY_BYTES (0x110000u / 2)
#define NT_MAX_PIECE (1024u * 1024)
#define NT_MEMO_KEYS 8192u
#define NT_MEMO_SLOTS 16384u
#define NT_MEMO_PAYLOAD (2u * 1024 * 1024)
#define NT_MEMO_KEY 256u

struct NtCounter {
  uint8_t *arena;
  uint32_t *offsets, *slots;
  uint8_t *categories;
  uint32_t max_token;
};
#include "native_pretokenize.h"

static void *nt_array(size_t n, size_t size, int zero) {
  if (!size || n > SIZE_MAX / size) return NULL;
  return zero ? calloc(n, size) : malloc(n * size);
}
static uint64_t nt_hash(const uint8_t *s, size_t n) {
  uint64_t h = UINT64_C(14695981039346656037);
  for (size_t i = 0; i < n; ++i) h = (h ^ s[i]) * UINT64_C(1099511628211);
  return h ^ (h >> 32);
}
static int32_t nt_rank(const NtCounter *c, const uint8_t *s, size_t n) {
  if (!n || n > c->max_token) return -1;
  uint32_t slot = (uint32_t)nt_hash(s, n) & (NT_SLOTS - 1);
  for (uint32_t probes = 0; probes < NT_SLOTS; ++probes) {
    uint32_t id = c->slots[slot];
    if (!id) return -1;
    --id;
    uint32_t off = c->offsets[id], len = c->offsets[id + 1] - off;
    if (len == n && !memcmp(c->arena + off, s, n)) return (int32_t)id;
    slot = (slot + 1) & (NT_SLOTS - 1);
  }
  return -1;
}
void nt_counter_free(NtCounter *c) {
  if (!c) return;
  free(c->arena);
  free(c->offsets);
  free(c->slots);
  free(c->categories);
  free(c);
}
static int nt_base64(uint8_t b) {
  if (b >= 'A' && b <= 'Z') return b - 'A';
  if (b >= 'a' && b <= 'z') return b - 'a' + 26;
  if (b >= '0' && b <= '9') return b - '0' + 52;
  return b == '+' ? 62 : b == '/' ? 63 : -1;
}
static int nt_read_ranks(NtCounter *c, const uint8_t *s, size_t n) {
  size_t p = 0, used = 0;
  uint32_t count = 0;
  while (p < n) {
    if (s[p] == '\n') { ++p; continue; }
    if (count >= NT_RANKS) return 0;
    size_t begin = p;
    while (p < n && s[p] != ' ' && s[p] != '\n') ++p;
    if (p == n || s[p] != ' ') return 0;
    size_t end = p, padding = 0;
    while (end > begin && s[end - 1] == '=') { --end; ++padding; }
    size_t tail = (end - begin) % 4;
    if (tail == 1 || padding > 2 ||
        (padding && ((p - begin) % 4 || tail + padding != 4))) return 0;
    c->offsets[count] = (uint32_t)used;
    uint32_t accum = 0;
    unsigned bits = 0;
    for (size_t i = begin; i < end; ++i) {
      int v = nt_base64(s[i]);
      if (v < 0) return 0;
      accum = (accum << 6) | (unsigned)v;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        if (used >= n) return 0;
        c->arena[used++] = (uint8_t)(accum >> bits);
      }
    }
    if ((bits && (accum & ((1u << bits) - 1))) || used == c->offsets[count]) return 0;
    uint32_t len = (uint32_t)used - c->offsets[count];
    if (len > c->max_token) c->max_token = len;
    ++p;
    size_t rank_begin = p;
    uint32_t rank = 0;
    while (p < n && s[p] != '\n') {
      unsigned digit = (unsigned)s[p++] - '0';
      if (digit > 9 || rank > (INT32_MAX - digit) / 10) return 0;
      rank = rank * 10 + digit;
    }
    if (p == rank_begin || rank != count) return 0;
    c->offsets[count + 1] = (uint32_t)used;
    uint32_t slot = (uint32_t)nt_hash(c->arena + c->offsets[count], len) & (NT_SLOTS - 1);
    while (c->slots[slot]) {
      uint32_t id = c->slots[slot] - 1;
      if (c->offsets[id + 1] - c->offsets[id] == len &&
          !memcmp(c->arena + c->offsets[id], c->arena + c->offsets[count], len)) return 0;
      slot = (slot + 1) & (NT_SLOTS - 1);
    }
    c->slots[slot] = ++count;
  }
  if (count != NT_RANKS) return 0;
  for (unsigned i = 0; i < 256; ++i) {
    uint8_t b = (uint8_t)i;
    if (nt_rank(c, &b, 1) < 0) return 0;
  }
  return 1;
}
static int nt_hex(const uint8_t *s, size_t n, uint32_t *out) {
  uint32_t v = 0;
  if (!n) return 0;
  for (size_t i = 0; i < n; ++i) {
    unsigned d = s[i] >= '0' && s[i] <= '9' ? s[i] - '0' :
                 s[i] >= 'A' && s[i] <= 'F' ? s[i] - 'A' + 10 :
                 s[i] >= 'a' && s[i] <= 'f' ? s[i] - 'a' + 10 : 16;
    if (d > 15 || v > (0x10ffffu - d) / 16) return 0;
    v = v * 16 + d;
  }
  *out = v;
  return 1;
}
static int nt_read_categories(NtCounter *c, const uint8_t *s, size_t n) {
  size_t p = 0;
  while (p < n) {
    size_t start = p;
    while (p < n && s[p] != '\n') ++p;
    size_t end = p;
    if (p < n) ++p;
    for (size_t i = start; i < end; ++i) if (s[i] == '#') { end = i; break; }
    while (start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r')) ++start;
    while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\r')) --end;
    if (start == end) continue;
    size_t semi = start;
    while (semi < end && s[semi] != ';') ++semi;
    if (semi == end) return 0;
    size_t cat = semi + 1;
    while (cat < end && (s[cat] == ' ' || s[cat] == '\t')) ++cat;
    if (end - cat != 2) return 0;
    unsigned mask = 0;
    if (s[cat] == 'L') {
      switch (s[cat + 1]) {
        case 'u': case 't': mask = 5; break;
        case 'l': mask = 6; break;
        case 'm': case 'o': mask = 7; break;
      }
    } else if (s[cat] == 'M' && (s[cat + 1] == 'n' || s[cat + 1] == 'c' || s[cat + 1] == 'e')) mask = 3;
    else if (s[cat] == 'N' && (s[cat + 1] == 'd' || s[cat + 1] == 'l' || s[cat + 1] == 'o')) mask = 8;
    if (!mask) continue;
    size_t range_end = semi;
    while (range_end > start && (s[range_end - 1] == ' ' || s[range_end - 1] == '\t')) --range_end;
    size_t dot = start;
    while (dot < range_end && s[dot] != '.') ++dot;
    uint32_t first, last;
    if (!nt_hex(s + start, dot - start, &first)) return 0;
    last = first;
    if (dot != range_end && (range_end - dot < 3 || s[dot + 1] != '.' ||
        !nt_hex(s + dot + 2, range_end - dot - 2, &last))) return 0;
    if (first > last) return 0;
    for (uint32_t cp = first; cp <= last; ++cp) {
      unsigned shift = (cp & 1) * 4;
      c->categories[cp >> 1] = (uint8_t)((c->categories[cp >> 1] & ~(15u << shift)) | (mask << shift));
    }
  }
  return 1;
}
NtCounter *nt_counter_new(const uint8_t *ranks, size_t ranks_len,
                          const uint8_t *unicode, size_t unicode_len) {
  // Only called after both digest and MoonBit format validators succeeded.
  // These bounds also keep every parser offset representable on 32-bit hosts.
  if (!ranks || !unicode || !ranks_len || ranks_len > 3613922 || unicode_len > 274423) return NULL;
  NtCounter *c = nt_array(1, sizeof(*c), 1);
  if (!c) return NULL;
  c->arena = nt_array(ranks_len, 1, 0);
  c->offsets = nt_array(NT_RANKS + 1, sizeof(uint32_t), 0);
  c->slots = nt_array(NT_SLOTS, sizeof(uint32_t), 1);
  c->categories = nt_array(NT_CATEGORY_BYTES, 1, 1);
  if (!c->arena || !c->offsets || !c->slots || !c->categories ||
      !nt_read_ranks(c, ranks, ranks_len) || !nt_read_categories(c, unicode, unicode_len)) {
    nt_counter_free(c);
    return NULL;
  }
  // Compact the upper-bound arena when possible; failure leaves valid storage.
  size_t used = c->offsets[NT_RANKS];
  uint8_t *arena = realloc(c->arena, used);
  if (arena) c->arena = arena;
  return c;
}

// Indexed heap: at most one candidate per surviving left symbol. Updating the
// two affected neighbors eliminates stale records. Storage is 24 bytes per
// capacity slot, rounded up to a power of two and capped at 24 MiB.
typedef struct { int32_t end, prev, next, rank, heap_pos; } NtNode;
_Static_assert(sizeof(NtNode) + sizeof(int32_t) == 24, "scratch slot layout");
typedef struct { NtNode *nodes; int32_t *heap; size_t capacity, size; } NtScratch;
static int nt_less(const NtScratch *s, int32_t a, int32_t b) {
  return s->nodes[a].rank < s->nodes[b].rank ||
         (s->nodes[a].rank == s->nodes[b].rank && a < b);
}
static void nt_heap_set(NtScratch *s, size_t i, int32_t pos) {
  s->heap[i] = pos;
  s->nodes[pos].heap_pos = (int32_t)i;
}
static void nt_heap_fix(NtScratch *s, size_t i) {
  int32_t pos = s->heap[i];
  while (i && nt_less(s, pos, s->heap[(i - 1) / 2])) {
    nt_heap_set(s, i, s->heap[(i - 1) / 2]);
    i = (i - 1) / 2;
  }
  while (i * 2 + 1 < s->size) {
    size_t child = i * 2 + 1;
    if (child + 1 < s->size && nt_less(s, s->heap[child + 1], s->heap[child])) ++child;
    if (!nt_less(s, s->heap[child], pos)) break;
    nt_heap_set(s, i, s->heap[child]);
    i = child;
  }
  nt_heap_set(s, i, pos);
}
static void nt_heap_remove(NtScratch *s, int32_t pos) {
  int32_t index = s->nodes[pos].heap_pos;
  if (index < 0) return;
  --s->size;
  s->nodes[pos].heap_pos = -1;
  if ((size_t)index == s->size) return;
  nt_heap_set(s, (size_t)index, s->heap[s->size]);
  nt_heap_fix(s, (size_t)index);
}
static void nt_candidate(const NtCounter *c, const uint8_t *word, NtScratch *s, int32_t pos) {
  if (pos < 0) return;
  NtNode *node = s->nodes + pos;
  int32_t right = node->next;
  int32_t rank = right < 0 ? -1 : nt_rank(c, word + pos, (size_t)(s->nodes[right].end - pos));
  if (rank < 0) { nt_heap_remove(s, pos); return; }
  node->rank = rank;
  if (node->heap_pos < 0) nt_heap_set(s, s->size++, pos);
  nt_heap_fix(s, (size_t)node->heap_pos);
}
static int nt_scratch_reserve(NtScratch *s, size_t n) {
  if (n > NT_MAX_PIECE) return 0;
  if (s->capacity >= n) return 1;
  size_t capacity = s->capacity ? s->capacity : 256;
  while (capacity < n) capacity *= 2; // capped power of two, <= NT_MAX_PIECE
  size_t unit = sizeof(NtNode) + sizeof(int32_t);
  // Previous pieces are complete: discard their contents before growth so
  // even the transient live C scratch allocation stays within 24 MiB. On OOM
  // the caller falls back exactly; it does not need the previous buffer.
  free(s->nodes);
  s->nodes = NULL;
  s->heap = NULL;
  s->capacity = 0;
  void *block = nt_array(capacity, unit, 0);
  if (!block) return 0;
  s->nodes = block;
  s->heap = (int32_t *)(s->nodes + capacity);
  s->capacity = capacity;
  return 1;
}
static int32_t nt_bpe(const NtCounter *c, const uint8_t *word, size_t n, NtScratch *s) {
  if (nt_rank(c, word, n) >= 0) return 1;
  if (!nt_scratch_reserve(s, n)) return -1;
  s->size = 0;
  for (size_t i = 0; i < n; ++i)
    s->nodes[i] = (NtNode){(int32_t)i + 1, (int32_t)i - 1, (int32_t)i + 1, -1, -1};
  s->nodes[n - 1].next = -1;
  for (size_t i = 0; i + 1 < n; ++i) nt_candidate(c, word, s, (int32_t)i);
  int32_t count = (int32_t)n;
  while (s->size) {
    int32_t pos = s->heap[0], right = s->nodes[pos].next;
    nt_heap_remove(s, pos);
    nt_heap_remove(s, right);
    s->nodes[pos].end = s->nodes[right].end;
    s->nodes[pos].next = s->nodes[right].next;
    s->nodes[right].next = -2;
    --count;
    int32_t next = s->nodes[pos].next;
    if (next >= 0) s->nodes[next].prev = pos;
    nt_candidate(c, word, s, s->nodes[pos].prev);
    nt_candidate(c, word, s, pos);
  }
  return count;
}

typedef struct { uint64_t hash; uint32_t offset, count; uint16_t len; } NtMemoEntry;
typedef struct {
  NtMemoEntry *entries;
  uint8_t *payload;
  size_t used, keys, slots, key_limit, payload_capacity;
  int attempted;
} NtMemo;
static void nt_memo_init(NtMemo *m, size_t input_len) {
  m->attempted = 1;
  m->key_limit = input_len / 2 < NT_MEMO_KEYS ? input_len / 2 : NT_MEMO_KEYS;
  m->payload_capacity = input_len < NT_MEMO_PAYLOAD ? input_len : NT_MEMO_PAYLOAD;
  m->slots = 2;
  while (m->slots < m->key_limit * 2) m->slots *= 2;
  m->entries = nt_array(m->slots, sizeof(NtMemoEntry), 1);
  if (m->entries) {
    m->payload = nt_array(m->payload_capacity, 1, 0);
    if (!m->payload) { free(m->entries); m->entries = NULL; }
  }
}
static int32_t nt_memo_get(const NtMemo *m, const uint8_t *s, size_t n, uint64_t h) {
  if (!m->entries || n > NT_MEMO_KEY) return -1;
  size_t slot = (size_t)h & (m->slots - 1);
  for (size_t i = 0; i < m->slots; ++i) {
    const NtMemoEntry *e = m->entries + slot;
    if (!e->len) return -1;
    if (e->hash == h && e->len == n && !memcmp(m->payload + e->offset, s, n)) return (int32_t)e->count;
    slot = (slot + 1) & (m->slots - 1);
  }
  return -1;
}
static void nt_memo_put(NtMemo *m, const uint8_t *s, size_t n, uint64_t h, int32_t count) {
  if (!n || n > NT_MEMO_KEY || m->keys >= m->key_limit || n > m->payload_capacity - m->used) return;
  if (!m->entries) return; // optional memo allocation failure never loses exactness
  size_t slot = (size_t)h & (m->slots - 1);
  while (m->entries[slot].len) slot = (slot + 1) & (m->slots - 1);
  memcpy(m->payload + m->used, s, n);
  m->entries[slot] = (NtMemoEntry){h, (uint32_t)m->used, (uint32_t)count, (uint16_t)n};
  m->used += n;
  ++m->keys;
}
int32_t nt_counter_count(const NtCounter *c, const uint8_t *text, size_t len) {
  if (!c || len > INT32_MAX || (!text && len)) return -1;
  if (!len) return 0;
  NtScratch scratch = {0};
  NtMemo memo = {0};
  size_t start = 0;
  int32_t total = 0;
  while (start < len) {
    size_t end = nt_piece_end(c, text, len, start);
    if (end <= start || end > len) { total = -1; break; }
    size_t n = end - start;
    const uint8_t *piece = text + start;
    int32_t count = 1;
    if (n > 1) {
      // Lazy, input-sized bounded memo; no per-piece allocation and no table
      // allocation at all for empty/single-byte-only documents.
      if (n <= NT_MEMO_KEY && !memo.attempted) nt_memo_init(&memo, len);
      uint64_t h = n <= NT_MEMO_KEY ? nt_hash(piece, n) : 0;
      count = nt_memo_get(&memo, piece, n, h);
      if (count < 0) {
        count = nt_bpe(c, piece, n, &scratch);
        if (count < 0) { total = -1; break; }
        nt_memo_put(&memo, piece, n, h, count);
      }
    }
    // count <= piece bytes, and len <= INT32_MAX, including the final sum.
    if (count > INT32_MAX - total) { total = -1; break; }
    total += count;
    start = end;
  }
  free(scratch.nodes);
  free(memo.entries);
  free(memo.payload);
  return total;
}
int32_t nt_counter_piece_end(const NtCounter *c, const uint8_t *text, size_t len, int32_t start) {
  if (!c || !text || len > INT32_MAX || start < 0 || (size_t)start >= len) return -1;
  size_t end = nt_piece_end(c, text, len, (size_t)start);
  return end > (size_t)start && end <= len ? (int32_t)end : -1;
}
