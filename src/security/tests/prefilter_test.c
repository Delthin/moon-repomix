#include "../prefilter.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  assert(pf_candidates(NULL, 0) == 0);
  const char *texts[] = {"github_pat_", "sk-", "pypi-AgEIcHlwaS5vcmc",
    "1//", "BeArEr ", "eyJ", "-----BEGIN ", "@ before ://"};
  const uint32_t bits[] = {PF_ACCESS, PF_ACCESS, PF_ACCESS, PF_ACCESS,
    PF_BEARER, PF_JWT, PF_PEM, PF_URL};
  for (size_t k = 0; k < sizeof(texts) / sizeof(texts[0]); ++k) {
    size_t length = strlen(texts[k]);
    for (size_t offset = 0; offset < 5; ++offset) {
      for (size_t cut = 0; cut <= length; ++cut) {
        size_t n = offset + cut;
        uint16_t *s = malloc(n ? n * sizeof(uint16_t) : 1);
        assert(s);
        for (size_t i = 0; i < offset; ++i) s[i] = (uint16_t)(0xd800 + i);
        for (size_t i = 0; i < cut; ++i) s[offset + i] = (uint8_t)texts[k][i];
        uint32_t flags = pf_candidates(s, n);
        assert((flags & ~31u) == 0);
        if (cut == length) assert(flags & bits[k]);
        free(s);
      }
    }
  }
  uint32_t random = 0x48a72f19;
  for (size_t round = 0; round < 4096; ++round) {
    size_t n = round % 193;
    uint16_t *s = malloc(n ? n * sizeof(uint16_t) : 1);
    assert(s);
    for (size_t i = 0; i < n; ++i) {
      random ^= random << 13; random ^= random >> 17; random ^= random << 5;
      s[i] = (uint16_t)random;
    }
    assert((pf_candidates(s, n) & ~31u) == 0);
    free(s);
  }
  puts("Credential necessary-prefix bounds: ASan/UBSan fixtures passed");
  return 0;
}
