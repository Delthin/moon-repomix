// Necessary literals only: detector decisions remain in pinned moon_scrub 0.5.2.
// Prefix inventory derived from its Apache-2.0 tokens.mbt/credentials.mbt;
// see LICENSES/moon-scrub-Apache-2.0.txt. No text or borrowed pointer escapes.
#ifndef MOON_REPOMIX_CREDENTIAL_PREFILTER_H
#define MOON_REPOMIX_CREDENTIAL_PREFILTER_H
#include <stddef.h>
#include <stdint.h>

enum { PF_ACCESS = 1, PF_BEARER = 2, PF_JWT = 4, PF_PEM = 8, PF_URL = 16 };
static int pf_at(const uint16_t *s, size_t n, size_t i, const char *p, size_t k) {
  if (k > n - i) return 0;
  for (size_t j = 0; j < k; ++j)
    if (s[i + j] != (uint8_t)p[j]) return 0;
  return 1;
}
static int pf_bearer(const uint16_t *s, size_t n, size_t i) {
  static const char p[] = "bearer ";
  if (7 > n - i) return 0;
  for (size_t j = 0; j < 7; ++j) {
    uint16_t c = s[i + j];
    if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    if (c != (uint8_t)p[j]) return 0;
  }
  return 1;
}
static int pf_access(const uint16_t *s, size_t n, size_t i, uint16_t first) {
  typedef struct { const char *text; uint8_t length; } Prefix;
#define PF_LITERAL(s) {s, sizeof(s) - 1}
  static const Prefix prefixes[] = {
    PF_LITERAL("1//"),
    PF_LITERAL("ATATTx"), PF_LITERAL("AIza"), PF_LITERAL("AKIA"), PF_LITERAL("ASIA"),
    PF_LITERAL("LTAI"), PF_LITERAL("SG."), PF_LITERAL("cko_"),
    PF_LITERAL("dop_v1_"), PF_LITERAL("dop_v2_"),
    PF_LITERAL("github_pat_"), PF_LITERAL("ghp_"), PF_LITERAL("gho_"),
    PF_LITERAL("ghu_"), PF_LITERAL("ghs_"), PF_LITERAL("ghr_"), PF_LITERAL("gha_"),
    PF_LITERAL("glpat-"), PF_LITERAL("glc_"), PF_LITERAL("glrt-"),
    PF_LITERAL("key-"), PF_LITERAL("lin_api_"), PF_LITERAL("npm_"), PF_LITERAL("nfp_"),
    PF_LITERAL("pk_live_"), PF_LITERAL("pypi-AgEIcHlwaS5vcmc"), PF_LITERAL("rk_live_"),
    PF_LITERAL("sk-ant-"), PF_LITERAL("sk_live_"), PF_LITERAL("shpat_"),
    PF_LITERAL("shpca_"), PF_LITERAL("shppa_"), PF_LITERAL("sntrys_"), PF_LITERAL("sk-"),
    PF_LITERAL("xoxb-"), PF_LITERAL("xoxp-"), PF_LITERAL("xoxc-"),
    PF_LITERAL("xoxa-"), PF_LITERAL("xoxr-"), PF_LITERAL("xoxe.x-xcs-")
  };
#undef PF_LITERAL
  size_t begin, end;
  switch (first) {
    case '1': begin = 0; end = 1; break;
    case 'A': begin = 1; end = 5; break;
    case 'L': begin = 5; end = 6; break;
    case 'S': begin = 6; end = 7; break;
    case 'c': begin = 7; end = 8; break;
    case 'd': begin = 8; end = 10; break;
    case 'g': begin = 10; end = 20; break;
    case 'k': begin = 20; end = 21; break;
    case 'l': begin = 21; end = 22; break;
    case 'n': begin = 22; end = 24; break;
    case 'p': begin = 24; end = 26; break;
    case 'r': begin = 26; end = 27; break;
    case 's': begin = 27; end = 34; break;
    case 'x': begin = 34; end = 40; break;
    default: return 0;
  }
  for (size_t j = begin; j < end; ++j)
    if (pf_at(s, n, i, prefixes[j].text, prefixes[j].length)) return 1;
  return 0;
}
static uint32_t pf_candidates(const uint16_t *s, size_t n) {
  uint32_t flags = 0;
  int scheme = 0, at = 0;
  for (size_t i = 0; i < n; ++i) {
    uint16_t c = s[i];
    if (!(flags & PF_ACCESS) && pf_access(s, n, i, c)) flags |= PF_ACCESS;
    if (!(flags & PF_BEARER) && (c == 'b' || c == 'B') && pf_bearer(s, n, i))
      flags |= PF_BEARER;
    if (!(flags & PF_JWT) && c == 'e' && pf_at(s, n, i, "eyJ", 3)) flags |= PF_JWT;
    if (!(flags & PF_PEM) && c == '-' && pf_at(s, n, i, "-----BEGIN ", 11)) flags |= PF_PEM;
    if (!(flags & PF_URL)) {
      if (c == '@') at = 1;
      if (c == ':' && pf_at(s, n, i, "://", 3)) scheme = 1;
      // Relative positions are unrestricted: false positives are resolved by
      // the unchanged full-text detector, never by this prepass.
      if (scheme && at) flags |= PF_URL;
    }
    if (flags == 31) break;
  }
  return flags;
}
#endif
