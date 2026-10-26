/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE. */
#ifndef MOON_REPOMIX_WORKER_POOL_H
#define MOON_REPOMIX_WORKER_POOL_H
#include <stdint.h>
typedef struct SCWorkerPool SCWorkerPool;
/* All functions except the private worker entry run on the owning main thread.
 * One staged/running batch per pool; results remain owned until release/close. */
SCWorkerPool *sc_pool_new(int workers);
int sc_pool_add(SCWorkerPool *, int language, const uint8_t *, uint32_t length);
int sc_pool_start(SCWorkerPool *);
int sc_pool_done(SCWorkerPool *);
const uint8_t *sc_pool_result(SCWorkerPool *, int index, uint32_t *length);
void sc_pool_release(SCWorkerPool *);
void sc_pool_stop(SCWorkerPool *);
int sc_pool_live(SCWorkerPool *);
/* Stop + join + free; callers normally poll live==0 asynchronously first. */
void sc_pool_delete(SCWorkerPool *);
#endif
