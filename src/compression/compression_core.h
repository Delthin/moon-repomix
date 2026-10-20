#ifndef MOON_REPOMIX_COMPRESSION_CORE_H
#define MOON_REPOMIX_COMPRESSION_CORE_H
#include <stdint.h>
/* A call-scoped byte selection. Caller frees keep with free(). */
typedef struct {
  uint8_t *keep;
  uint32_t length;
  int32_t status;
} SCPlan;
/* Status: 0 success, 1 parse-error, 2 timeout, 3 resource-limit,
 * 4 parser-unavailable. Languages: 0 JS, 1 TS, 2 TSX, 3 Python. */
SCPlan sc_plan(int32_t language, const char *source, uint32_t length,
               uint64_t timeout_micros);
#endif
