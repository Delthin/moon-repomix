/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE.
 * Main-thread-only managed bridge; worker_pool.c never calls this file. */
#include <moonbit.h>
#include <string.h>
#include "worker_pool.h"
typedef struct { SCWorkerPool *pool; } PoolHandle;
static void finalize_pool(void *payload) {
  PoolHandle *h = payload;
  sc_pool_delete(h->pool);
  h->pool = NULL;
}
MOONBIT_FFI_EXPORT PoolHandle *moon_repomix_pool_new(int32_t workers) {
  PoolHandle *h = moonbit_make_external_object(finalize_pool, sizeof(PoolHandle));
  h->pool = sc_pool_new(workers);
  return h;
}
MOONBIT_FFI_EXPORT int32_t moon_repomix_pool_available(PoolHandle *h) {
  return h->pool != NULL;
}
MOONBIT_FFI_EXPORT int32_t moon_repomix_pool_add(PoolHandle *h, int32_t language,
                                              moonbit_bytes_t source) {
  return sc_pool_add(h->pool, language, source, (uint32_t)Moonbit_array_length(source));
}
MOONBIT_FFI_EXPORT int32_t moon_repomix_pool_start(PoolHandle *h) { return sc_pool_start(h->pool); }
MOONBIT_FFI_EXPORT int32_t moon_repomix_pool_done(PoolHandle *h) { return sc_pool_done(h->pool); }
MOONBIT_FFI_EXPORT void moon_repomix_pool_release(PoolHandle *h) { sc_pool_release(h->pool); }
MOONBIT_FFI_EXPORT void moon_repomix_pool_stop(PoolHandle *h) { sc_pool_stop(h->pool); }
MOONBIT_FFI_EXPORT int32_t moon_repomix_pool_live(PoolHandle *h) { return sc_pool_live(h->pool); }
MOONBIT_FFI_EXPORT void moon_repomix_pool_dispose(PoolHandle *h) { finalize_pool(h); }
MOONBIT_FFI_EXPORT moonbit_bytes_t moon_repomix_pool_result(PoolHandle *h, int32_t index) {
  uint32_t length = 0;
  const uint8_t *wire = sc_pool_result(h->pool, index, &length);
  if (!wire) return moonbit_make_bytes(0, 0);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, wire, length);
  return result;
}
