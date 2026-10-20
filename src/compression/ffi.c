#include <moonbit.h>
#include <stdlib.h>
#include "compression_core.h"

static void put_u32(uint8_t *out, uint32_t value) {
  for (int i = 0; i < 4; ++i) out[i] = (uint8_t)(value >> (8 * i));
}

/* Borrowed input is used only until sc_plan returns. All parser/tree/mask
 * allocations are freed here; the result contains no C pointers. Wire format:
 * LE u32 status, followed by (byte start, byte end, first line, last line). */
MOONBIT_FFI_EXPORT moonbit_bytes_t moon_repomix_structure_plan(
    int32_t language, moonbit_bytes_t source) {
  uint32_t length = (uint32_t)Moonbit_array_length(source);
  SCPlan plan = sc_plan(language, (const char *)source, length, 200000);
  uint32_t count = 0;
  if (!plan.status) {
    for (uint32_t i = 0; i < length; ++i)
      if (plan.keep[i] && (i == 0 || !plan.keep[i - 1])) ++count;
    if (count > 65536) plan.status = 3;
  }
  if (plan.status) count = 0;
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)(4 + count * 16), 0);
  put_u32(out, (uint32_t)plan.status);
  if (!plan.status) {
    uint32_t line = 1, offset = 4;
    for (uint32_t i = 0; i < length;) {
      if (!plan.keep[i]) {
        if (source[i++] == '\n') ++line;
        continue;
      }
      uint32_t start = i, first_line = line;
      while (i < length && plan.keep[i]) {
        if (source[i++] == '\n') ++line;
      }
      put_u32(out + offset, start);
      put_u32(out + offset + 4, i);
      put_u32(out + offset + 8, first_line);
      put_u32(out + offset + 12, line - (source[i - 1] == '\n' ? 1 : 0));
      offset += 16;
    }
  }
  free(plan.keep);
  return out;
}
