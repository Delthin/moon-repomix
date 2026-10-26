// Necessary conditions only: detector decisions remain in pinned moon_scrub 0.5.2.
// Prefix/key inventory derived from its Apache-2.0 tokens.mbt/credentials.mbt;
// see LICENSES/moon-scrub-Apache-2.0.txt. No text or borrowed pointer escapes.
#ifndef MOON_REPOMIX_CREDENTIAL_PREFILTER_H
#define MOON_REPOMIX_CREDENTIAL_PREFILTER_H
#include <stddef.h>
#include <stdint.h>

enum {
  PF_ACCESS = 1, PF_BEARER = 2, PF_JWT = 4, PF_PEM = 8, PF_URL = 16,
  PF_ASSIGNMENT = 32
};
static int pf_at(const uint16_t *s, size_t n, size_t i, const char *p, size_t k) {
  if (k > n - i) return 0;
  for (size_t j = 0; j < k; ++j)
    if (s[i + j] != (uint8_t)p[j]) return 0;
  return 1;
}
static int pf_at_ci(const uint16_t *s, size_t n, size_t i,
                    const char *p, size_t length) {
  if (length > n - i) return 0;
  for (size_t j = 0; j < length; ++j) {
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
static int pf_letter(uint16_t c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}
static int pf_key_char(uint16_t c) {
  return pf_letter(c) || (c >= '0' && c <= '9') || c == '_' || c == '-';
}
static int pf_assignment(const uint16_t *s, size_t n, size_t i, uint16_t c) {
  if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
  // Both Basic Auth anchors contain this word, even inside another word.
  if (c == 'a' && pf_at_ci(s, n, i, "authorization", 13)) return 1;
  // A preceding letter/underscore belongs to the same engine key. Digits and
  // '-' are deliberately not excluded: the engine can start a key after them.
  if (i && (pf_letter(s[i - 1]) || s[i - 1] == '_')) return 0;
  typedef struct { const char *text; uint8_t length; } Key;
#define PF_KEY(s) {s, sizeof(s) - 1}
  static const Key keys[] = {
    PF_KEY("account_key"), PF_KEY("api_key"), PF_KEY("apikey"),
    PF_KEY("auth_token"), PF_KEY("authorization"), PF_KEY("aws_secret_access_key"),
    PF_KEY("client_secret"), PF_KEY("credential"),
    PF_KEY("passphrase"), PF_KEY("passwd"), PF_KEY("password"),
    PF_KEY("private_key"), PF_KEY("private_token"), PF_KEY("pwd"),
    PF_KEY("refresh_token"),
    PF_KEY("secret"), PF_KEY("secret_key"), PF_KEY("session_key"),
    PF_KEY("shared_access_key"), PF_KEY("sharedaccesskey"),
    PF_KEY("token")
  };
#undef PF_KEY
  size_t begin, end;
  switch (c) {
    case 'a': begin = 0; end = 6; break;
    case 'c': begin = 6; end = 8; break;
    case 'p': begin = 8; end = 14; break;
    case 'r': begin = 14; end = 15; break;
    case 's': begin = 15; end = 20; break;
    case 't': begin = 20; end = 21; break;
    default: return 0;
  }
  for (size_t j = begin; j < end; ++j) {
    if (!pf_at_ci(s, n, i, keys[j].text, keys[j].length)) continue;
    size_t sep = i + keys[j].length;
    if (sep < n && pf_key_char(s[sep])) continue;
    if (sep < n && (s[sep] == '\"' || s[sep] == '\'')) ++sep;
    while (sep < n && (s[sep] == ' ' || s[sep] == '\t')) ++sep;
    if (sep < n && (s[sep] == '=' || s[sep] == ':')) return 1;
  }
  return 0;
}
static uint32_t pf_candidates(const uint16_t *s, size_t n) {
  uint32_t flags = 0;
  int scheme = 0, at = 0;
  for (size_t i = 0; i < n; ++i) {
    uint16_t c = s[i];
    if (!(flags & PF_ACCESS) && pf_access(s, n, i, c)) flags |= PF_ACCESS;
    if (!(flags & PF_BEARER) && (c == 'b' || c == 'B') &&
        pf_at_ci(s, n, i, "bearer ", 7))
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
    if (!(flags & PF_ASSIGNMENT) && pf_assignment(s, n, i, c))
      flags |= PF_ASSIGNMENT;
    if (flags == 63) break;
  }
  return flags;
}
#endif
