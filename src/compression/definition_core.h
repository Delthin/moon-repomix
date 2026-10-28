/* Copyright (c) 2026 moon-repomix contributors. MIT licensed. */
#ifndef MOON_REPOMIX_DEFINITION_CORE_H
#define MOON_REPOMIX_DEFINITION_CORE_H
#include <stdint.h>

#define SD_MAX_INPUT (8u * 1024u * 1024u)
#define SD_MAX_NODES 500000u
#define SD_MAX_VISITS 1000000u
#define SD_MAX_DEFINITIONS 4096u
#define SD_MAX_REFS 256u
#define SD_MAX_TOTAL_REFS 65536u
#define SD_MAX_DEPTH 256u
#define SD_MAX_NAME 4096u
#define SD_MAX_WIRE (16u * 1024u * 1024u)
#define SD_PARSE_MICROS 200000u

/* Status: 0 success, 1 parse-error, 2 timeout, 3 resource-limit,
 * 4 parser-unavailable, 6 unsupported-language. Failure always has wire=NULL.
 * Success wire: LE u32 status=0, count; then per definition
 * start_line, end_line, name_bytes, qualified_bytes, ref_count (all u32),
 * name, qualified_name, then repeated (u32 byte_length, UTF-8 reference).
 * Owns wire; caller frees it. No source/tree pointers survive this call. */
typedef struct {
  uint8_t *wire;
  uint32_t length;
  int32_t status;
} SDIndex;
SDIndex sd_index(int32_t language, const char *source, uint32_t length,
                 uint64_t timeout_micros);
#endif
