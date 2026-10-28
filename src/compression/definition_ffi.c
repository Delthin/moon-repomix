/* Copyright (c) 2026 moon-repomix contributors. MIT licensed. */
#include <moonbit.h>
#include <stdlib.h>
#include <string.h>
#include "definition_core.h"

/* Borrow ends before return. All C-owned memory is released after a copy into
 * managed Bytes; neither a node nor a source/native allocation escapes. */
MOONBIT_FFI_EXPORT moonbit_bytes_t moon_repomix_definition_index(
    int32_t language, moonbit_bytes_t source) {
  SDIndex index = sd_index(language, (const char *)source,
    (uint32_t)Moonbit_array_length(source), SD_PARSE_MICROS);
  moonbit_bytes_t out = moonbit_make_bytes(index.status ? 8 : (int32_t)index.length, 0);
  if (index.status) {
    for (unsigned i = 0; i < 4; ++i) out[i] = (uint8_t)((uint32_t)index.status >> (8 * i));
  } else {
    memcpy(out, index.wire, index.length);
  }
  free(index.wire);
  return out;
}
