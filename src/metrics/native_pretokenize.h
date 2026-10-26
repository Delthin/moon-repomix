// Ordered o200k_base alternatives from tiktoken 0.14.0 (MIT; see
// LICENSES/tokenizer-tiktoken-MIT.txt). Port of pretokenize.mbt, not a host regex.
// Input is the valid UTF-8 snapshot produced by MoonBit's strict encoder.
#ifndef MOON_REPOMIX_NATIVE_PRETOKENIZE_H
#define MOON_REPOMIX_NATIVE_PRETOKENIZE_H

static uint32_t nt_scalar(const uint8_t *s, size_t n, size_t p) {
  uint32_t c = s[p];
  if (c < 128) return c;
  // Bounds checks also protect private probes from truncated byte sequences.
  if (c >= 0xc2 && c < 0xe0 && n - p >= 2)
    return ((c & 31) << 6) | (s[p + 1] & 63);
  if (c >= 0xe0 && c < 0xf0 && n - p >= 3)
    return ((c & 15) << 12) | ((s[p + 1] & 63) << 6) | (s[p + 2] & 63);
  if (c >= 0xf0 && c <= 0xf4 && n - p >= 4)
    return ((c & 7) << 18) | ((s[p + 1] & 63) << 12) |
           ((s[p + 2] & 63) << 6) | (s[p + 3] & 63);
  return 0x110000;
}
static size_t nt_width(uint32_t c) {
  return c < 128 || c == 0x110000 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
}
static unsigned nt_category(const NtCounter *c, uint32_t cp) {
  if (cp >= 0x110000) return 0;
  return (c->categories[cp >> 1] >> ((cp & 1) * 4)) & 15;
}
static int nt_space(uint32_t c) {
  return (c >= 9 && c <= 13) || c == 0x20 || c == 0x85 || c == 0xa0 ||
         c == 0x1680 || (c >= 0x2000 && c <= 0x200a) || c == 0x2028 ||
         c == 0x2029 || c == 0x202f || c == 0x205f || c == 0x3000;
}
static size_t nt_letter_end(const NtCounter *c, const uint8_t *s, size_t n,
                            size_t start, int branch) {
  size_t end = start, last_lower = 0;
  while (end < n) {
    uint32_t cp = nt_scalar(s, n, end);
    unsigned cat = nt_category(c, cp);
    if (!(cat & 1)) break;
    end += nt_width(cp);
    if (cat & 2) last_lower = end;
  }
  if (branch == 1 && end == start) return 0;
  size_t lower_start = end;
  while (end < n) {
    uint32_t cp = nt_scalar(s, n, end);
    if (!(nt_category(c, cp) & 2)) break;
    end += nt_width(cp);
  }
  if (branch == 1 || end > lower_start) return end;
  return last_lower > start ? last_lower : 0;
}
static size_t nt_contraction(const uint8_t *s, size_t n, size_t end) {
  if (n - end < 2 || s[end] != '\'') return end;
  uint32_t cp = nt_scalar(s, n, end + 1);
  switch (cp) {
    case 's': case 'S': case 0x17f: case 't': case 'T':
    case 'm': case 'M': case 'd': case 'D': return end + 1 + nt_width(cp);
    case 'r': case 'R': case 'v': case 'V':
      return n - end >= 3 && (s[end + 2] == 'e' || s[end + 2] == 'E') ? end + 3 : end;
    case 'l': case 'L':
      return n - end >= 3 && (s[end + 2] == 'l' || s[end + 2] == 'L') ? end + 3 : end;
    default: return end;
  }
}
// In ASCII the two ordered letter branches both reduce to upper* lower*.
// A lower->upper transition ends this piece. Only an ASCII non-CR/LF,
// non-letter/digit may prefix it. A non-ASCII extension boundary must use the
// original Unicode branches, including their overlapping Lm/Lo/M categories.
static size_t nt_ascii_letter_end(const uint8_t *s, size_t n, size_t start) {
  size_t end = start;
  unsigned first = s[end];
  if ((unsigned)((first | 32u) - 'a') >= 26) {
    if (first >= 128 || first == '\r' || first == '\n' ||
        (first >= '0' && first <= '9') || ++end == n ||
        (unsigned)((s[end] | 32u) - 'a') >= 26) return 0;
  }
  unsigned lower = 0;
  while (end < n) {
    unsigned b = s[end];
    if ((unsigned)((b | 32u) - 'a') >= 26 || (!(b & 32u) && lower)) break;
    lower |= b & 32u;
    ++end;
  }
  if (end < n && s[end] >= 128) return 0;
  // Shared case-insensitive suffix logic also handles Unicode long-s (ſ).
  return nt_contraction(s, n, end);
}
static size_t nt_piece_end_general(const NtCounter *c, const uint8_t *s, size_t n,
                                   size_t start) {
  uint32_t first = nt_scalar(s, n, start);
  size_t after = start + nt_width(first);
  unsigned cat = nt_category(c, first);
  int prefix = first != '\r' && first != '\n' && !(cat & 12);
  for (int branch = 0; branch < 2; ++branch) {
    size_t end;
    if (prefix && (end = nt_letter_end(c, s, n, after, branch)))
      return nt_contraction(s, n, end);
    if ((end = nt_letter_end(c, s, n, start, branch)))
      return nt_contraction(s, n, end);
  }
  if (cat & 8) {
    size_t end = after;
    for (int i = 0; i < 2 && end < n; ++i) {
      uint32_t cp = nt_scalar(s, n, end);
      if (!(nt_category(c, cp) & 8)) break;
      end += nt_width(cp);
    }
    return end;
  }
  size_t punct = first == ' ' ? after : start, end = punct;
  while (end < n) {
    uint32_t cp = nt_scalar(s, n, end);
    if (nt_space(cp) || (nt_category(c, cp) & 12)) break;
    end += nt_width(cp);
  }
  if (end > punct) {
    while (end < n && (s[end] == '\r' || s[end] == '\n' || s[end] == '/')) ++end;
    return end;
  }
  size_t newline = start, last_space = start;
  end = start;
  while (end < n) {
    uint32_t cp = nt_scalar(s, n, end);
    if (!nt_space(cp)) break;
    last_space = end;
    end += nt_width(cp);
    if (cp == '\r' || cp == '\n') newline = end;
  }
  if (newline > start) return newline;
  if (end == n) return end;
  return last_space > start ? last_space : end;
}
static size_t nt_piece_end(const NtCounter *c, const uint8_t *s, size_t n,
                           size_t start) {
  size_t end = nt_ascii_letter_end(s, n, start);
  return end ? end : nt_piece_end_general(c, s, n, start);
}
#endif
