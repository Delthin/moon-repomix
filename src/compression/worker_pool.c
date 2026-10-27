/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE.
 * Workers only touch C-owned storage. No MoonBit runtime calls here. */
#include "worker_pool.h"
#include "compression_core.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
typedef HANDLE Thread;
typedef SRWLOCK Mutex;
typedef CONDITION_VARIABLE Condition;
#define LOCK(m) AcquireSRWLockExclusive(m)
#define UNLOCK(m) ReleaseSRWLockExclusive(m)
#define WAKE(c) WakeAllConditionVariable(c)
#define WAIT(c,m) SleepConditionVariableSRW(c,m,INFINITE,0)
#else
#include <pthread.h>
typedef pthread_t Thread;
typedef pthread_mutex_t Mutex;
typedef pthread_cond_t Condition;
#define LOCK(m) pthread_mutex_lock(m)
#define UNLOCK(m) pthread_mutex_unlock(m)
#define WAKE(c) pthread_cond_broadcast(c)
#define WAIT(c,m) pthread_cond_wait(c,m)
#endif

typedef struct {
  int language;
  uint8_t *source, *wire;
  uint32_t length, wire_length;
} Task;
struct SCWorkerPool {
  Mutex mutex;
  Condition ready;
  Thread threads[4];
  int created, live, stop, active, count, next, completed, reserved_workers;
  uint32_t bytes;
  SCAtomicBool cancel;
  Task tasks[4];
};
/* Process-wide reservations prevent multiple planners from multiplying the
 * hard budgets. Only reservation counters are shared between pools. */
static SCAtomicUInt reserved_workers = SC_ATOMIC_UINT_ZERO;
static SCAtomicUInt reserved_tasks = SC_ATOMIC_UINT_ZERO;
static SCAtomicUInt reserved_bytes = SC_ATOMIC_UINT_ZERO;
static bool reserve(SCAtomicUInt *counter, unsigned amount, unsigned limit) {
  unsigned current = sc_atomic_uint_load(counter);
  do {
    if (amount > limit || current > limit - amount) return false;
  } while (!sc_atomic_uint_compare_exchange_weak(counter, &current, current + amount));
  return true;
}
static bool cancelled(SCWorkerPool *p) {
  return sc_atomic_bool_load(&p->cancel);
}
static void put_u32(uint8_t *out, uint32_t value) {
  for (int i = 0; i < 4; ++i) out[i] = (uint8_t)(value >> (8 * i));
}
static void execute(SCWorkerPool *p, Task *t) {
  SCPlan plan = sc_plan_cancelable(t->language, (const char *)t->source,
                                   t->length, 200000, &p->cancel);
  uint32_t count = 0;
  if (!plan.status) {
    for (uint32_t i = 0; i < t->length; ++i) {
      if ((i & 4095) == 0 && cancelled(p)) { plan.status = 5; break; }
      if (plan.keep[i] && (i == 0 || !plan.keep[i - 1])) ++count;
    }
    if (!plan.status && count > 65536) plan.status = 3;
  }
  if (plan.status) count = 0;
  t->wire_length = 4 + count * 16;
  t->wire = malloc(t->wire_length);
  if (t->wire) {
    put_u32(t->wire, (uint32_t)plan.status);
    if (!plan.status) {
      uint32_t line = 1, offset = 4;
      for (uint32_t i = 0; i < t->length;) {
        if ((i & 4095) == 0 && cancelled(p)) break;
        if (!plan.keep[i]) {
          if (t->source[i++] == '\n') ++line;
          continue;
        }
        uint32_t start = i, first_line = line;
        while (i < t->length && plan.keep[i]) {
          if ((i & 4095) == 0 && cancelled(p)) break;
          if (t->source[i++] == '\n') ++line;
        }
        if (cancelled(p)) break;
        put_u32(t->wire + offset, start);
        put_u32(t->wire + offset + 4, i);
        put_u32(t->wire + offset + 8, first_line);
        put_u32(t->wire + offset + 12, line - (t->source[i - 1] == '\n' ? 1 : 0));
        offset += 16;
      }
    }
    if (cancelled(p)) { put_u32(t->wire, 5); t->wire_length = 4; }
  }
  free(plan.keep);
}
#ifdef _WIN32
static DWORD WINAPI worker(void *arg) {
#else
static void *worker(void *arg) {
#endif
  SCWorkerPool *p = arg;
  LOCK(&p->mutex);
  for (;;) {
    while (!p->stop && (!p->active || p->next == p->count))
      WAIT(&p->ready, &p->mutex);
    if (p->stop) break;
    int index = p->next++;
    UNLOCK(&p->mutex);
    execute(p, &p->tasks[index]);
    LOCK(&p->mutex);
    ++p->completed;
  }
  --p->live;
  UNLOCK(&p->mutex);
#ifdef _WIN32
  return 0;
#else
  return NULL;
#endif
}
SCWorkerPool *sc_pool_new(int workers) {
  if (workers < 1 || workers > 4) return NULL;
  SCWorkerPool *p = calloc(1, sizeof(*p));
  if (!p) return NULL;
  if (!reserve(&reserved_workers, (unsigned)workers, 4)) { free(p); return NULL; }
  p->reserved_workers = workers;
  sc_atomic_bool_init(&p->cancel, false);
#ifdef _WIN32
  InitializeSRWLock(&p->mutex);
  InitializeConditionVariable(&p->ready);
#else
  if (pthread_mutex_init(&p->mutex, NULL)) {
    sc_atomic_uint_fetch_sub(&reserved_workers, (unsigned)workers);
    free(p); return NULL;
  }
  if (pthread_cond_init(&p->ready, NULL)) {
    pthread_mutex_destroy(&p->mutex);
    sc_atomic_uint_fetch_sub(&reserved_workers, (unsigned)workers);
    free(p); return NULL;
  }
#endif
  for (int i = 0; i < workers; ++i) {
    /* Count before create: entry/exit also takes the mutex. */
    LOCK(&p->mutex);
    ++p->live;
#ifdef _WIN32
    p->threads[i] = CreateThread(NULL, 0, worker, p, 0, NULL);
    int failed = !p->threads[i];
#else
    int failed = pthread_create(&p->threads[i], NULL, worker, p) != 0;
#endif
    if (failed) --p->live;
    else ++p->created;
    UNLOCK(&p->mutex);
    if (failed) { sc_pool_delete(p); return NULL; }
  }
  return p;
}
int sc_pool_add(SCWorkerPool *p, int language, const uint8_t *source, uint32_t length) {
  if (!p || p->stop || p->active || p->count == 4 || language < 0 || language > 7 ||
      length > 8u * 1024 * 1024 || length > 16u * 1024 * 1024 - p->bytes) return 0;
  if (!reserve(&reserved_tasks, 1, 4)) return 0;
  if (!reserve(&reserved_bytes, length, 16u * 1024 * 1024)) {
    sc_atomic_uint_fetch_sub(&reserved_tasks, 1);
    return 0;
  }
  uint8_t *copy = malloc(length ? length : 1);
  if (!copy) {
    sc_atomic_uint_fetch_sub(&reserved_tasks, 1);
    sc_atomic_uint_fetch_sub(&reserved_bytes, length);
    return 0;
  }
  if (length) memcpy(copy, source, length);
  p->tasks[p->count++] = (Task){language, copy, NULL, length, 0};
  p->bytes += length;
  return 1;
}
int sc_pool_start(SCWorkerPool *p) {
  if (!p) return 0;
  LOCK(&p->mutex);
  int ok = !p->stop && !p->active;
  if (ok) { p->active = 1; WAKE(&p->ready); }
  UNLOCK(&p->mutex);
  return ok;
}
int sc_pool_done(SCWorkerPool *p) {
  if (!p) return 0;
  LOCK(&p->mutex);
  int done = p->active && !p->stop && p->completed == p->count;
  UNLOCK(&p->mutex);
  return done;
}
const uint8_t *sc_pool_result(SCWorkerPool *p, int index, uint32_t *length) {
  if (!sc_pool_done(p) || index < 0 || index >= p->count) return NULL;
  *length = p->tasks[index].wire_length;
  return p->tasks[index].wire;
}
void sc_pool_release(SCWorkerPool *p) {
  if (!p) return;
  LOCK(&p->mutex);
  /* Also permits abandoning an unstarted staging batch. */
  if (!p->active || p->completed == p->count || (p->stop && p->live == 0)) {
    for (int i = 0; i < p->count; ++i) {
      free(p->tasks[i].source);
      free(p->tasks[i].wire);
      memset(&p->tasks[i], 0, sizeof(Task));
    }
    sc_atomic_uint_fetch_sub(&reserved_tasks, (unsigned)p->count);
    sc_atomic_uint_fetch_sub(&reserved_bytes, p->bytes);
    p->active = p->count = p->next = p->completed = 0;
    p->bytes = 0;
  }
  UNLOCK(&p->mutex);
}
void sc_pool_stop(SCWorkerPool *p) {
  if (!p) return;
  sc_atomic_bool_store(&p->cancel, true);
  LOCK(&p->mutex);
  p->stop = 1;
  WAKE(&p->ready);
  UNLOCK(&p->mutex);
}
int sc_pool_live(SCWorkerPool *p) {
  if (!p) return 0;
  LOCK(&p->mutex);
  int live = p->live;
  UNLOCK(&p->mutex);
  return live;
}
void sc_pool_delete(SCWorkerPool *p) {
  if (!p) return;
  sc_pool_stop(p);
  for (int i = 0; i < p->created; ++i) {
#ifdef _WIN32
    WaitForSingleObject(p->threads[i], INFINITE);
    CloseHandle(p->threads[i]);
#else
    pthread_join(p->threads[i], NULL);
#endif
  }
  sc_pool_release(p);
#ifndef _WIN32
  pthread_cond_destroy(&p->ready);
  pthread_mutex_destroy(&p->mutex);
#endif
  sc_atomic_uint_fetch_sub(&reserved_workers, (unsigned)p->reserved_workers);
  free(p);
}
