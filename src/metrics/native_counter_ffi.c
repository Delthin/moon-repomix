// Borrowed MoonBit bytes never escape a call. The external object owns only
// the C counter; its finalizer releases inner allocations, not the container.
#include <moonbit.h>
#include "native_counter.h"

typedef struct { NtCounter *counter; } NtHandle;
static void nt_handle_finalize(void *object) {
  NtHandle *h = object;
  nt_counter_free(h->counter);
}
MOONBIT_FFI_EXPORT NtHandle *moon_repomix_counter_new(moonbit_bytes_t ranks,
                                                     moonbit_bytes_t unicode) {
  NtHandle *h = moonbit_make_external_object(nt_handle_finalize, sizeof(NtHandle));
  h->counter = nt_counter_new(ranks, (size_t)Moonbit_array_length(ranks),
                              unicode, (size_t)Moonbit_array_length(unicode));
  return h;
}
MOONBIT_FFI_EXPORT int32_t moon_repomix_counter_count(const NtHandle *h, moonbit_bytes_t text) {
  return nt_counter_count(h->counter, text, (size_t)Moonbit_array_length(text));
}
MOONBIT_FFI_EXPORT int32_t moon_repomix_counter_piece_end(const NtHandle *h,
                                                         moonbit_bytes_t text, int32_t start) {
  return nt_counter_piece_end(h->counter, text, (size_t)Moonbit_array_length(text), start);
}
