// Private, single-threaded count kernel. All returned storage is C-owned.
#ifndef MOON_REPOMIX_NATIVE_COUNTER_H
#define MOON_REPOMIX_NATIVE_COUNTER_H
#include <stddef.h>
#include <stdint.h>

typedef struct NtCounter NtCounter;
NtCounter *nt_counter_new(const uint8_t *ranks, size_t ranks_len,
                          const uint8_t *unicode, size_t unicode_len);
void nt_counter_free(NtCounter *counter);
// -1 requests the exact MoonBit fallback; never a partial/approximate count.
int32_t nt_counter_count(const NtCounter *counter, const uint8_t *text, size_t len);
// Private boundary probe shared by the FFI differential tests.
int32_t nt_counter_piece_end(const NtCounter *counter, const uint8_t *text,
                             size_t len, int32_t start);
#endif
