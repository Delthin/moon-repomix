/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE.
 * Synthetic standalone ownership/cancellation/limits/differential harness.
 * No MoonBit runtime or managed allocator is linked into this executable. */
#include "../worker_pool.h"
#include "../compression_core.h"
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>
#include <stdatomic.h>
static atomic_int alloc_fail = -1, thread_fail = -1;
static int fail_now(atomic_int *counter) {
  int n = atomic_load(counter);
  while (n >= 0) {
    if (atomic_compare_exchange_weak(counter, &n, n ? n - 1 : -1)) return n == 0;
  }
  return 0;
}
void *sc_test_malloc(size_t n) { return fail_now(&alloc_fail) ? NULL : malloc(n); }
void *sc_test_calloc(size_t n, size_t size) { return fail_now(&alloc_fail) ? NULL : calloc(n, size); }
int sc_test_pthread_create(pthread_t *t, const pthread_attr_t *a, void *(*f)(void *), void *p) {
  return fail_now(&thread_fail) ? 11 : pthread_create(t, a, f, p);
}
static void pause_poll(void) {
  const struct timespec ts = {0, 1000000};
  nanosleep(&ts, NULL);
}
static void wait_done(SCWorkerPool *p) { while (!sc_pool_done(p)) pause_poll(); }
static void stop_join(SCWorkerPool *p) {
  sc_pool_stop(p);
  while (sc_pool_live(p)) pause_poll();
  assert(sc_pool_live(p) == 0);
  sc_pool_stop(p);
  sc_pool_delete(p);
}
static uint32_t u32(const uint8_t *p) {
  return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static void check_result(SCWorkerPool *p, int index, int language, const char *source) {
  size_t size = strlen(source);
  SCPlan serial = sc_plan(language, source, (uint32_t)size, 200000);
  uint32_t length = 0;
  const uint8_t *wire = sc_pool_result(p, index, &length);
  assert(wire && length >= 4 && (length - 4) % 16 == 0);
  assert(u32(wire) == (uint32_t)serial.status);
  if (serial.status) assert(length == 4);
  else {
    uint8_t *actual = calloc(size ? size : 1, 1);
    assert(actual);
    uint32_t previous = 0;
    for (uint32_t offset = 4; offset < length; offset += 16) {
      uint32_t start = u32(wire + offset), end = u32(wire + offset + 4);
      assert(start >= previous && start < end && end <= size);
      memset(actual + start, 1, end - start);
      /* Independent range oracle counts original newlines at both endpoints. */
      uint32_t first = 1, last = 1;
      for (uint32_t i = 0; i < start; ++i) first += source[i] == '\n';
      for (uint32_t i = 0; i < end; ++i) last += source[i] == '\n';
      last -= source[end - 1] == '\n';
      assert(u32(wire + offset + 8) == first);
      assert(u32(wire + offset + 12) == last);
      previous = end;
    }
    assert(memcmp(actual, serial.keep, size) == 0);
    free(actual);
  }
  free(serial.keep);
}
static const char *fixtures[] = {
  "// café\r\nexport function f(x) {\r\n  return x + 123456789;\r\n}\r\n",
  "export function f(x: number): number { return x + 123456789; }\n",
  "export function F() { return <div>hello world</div>; }\n",
  "# café\r\ndef f(x):\r\n    return x + 123456789\r\n",
  "pub fn f(x : Int) -> Int { x + 123456789 }\n",
  "package p\nfunc F(x int) int { return x + 123456789 }\n",
  "pub fn f(x: i32) -> i32 { x + 123456789 }\n",
  "class C { int f(int x) { return x + 123456789; } }\n",
};
static void differential(void) {
  const int workers[] = {1, 2, 4};
  for (int w = 0; w < 3; ++w) {
    SCWorkerPool *p = sc_pool_new(workers[w]);
    assert(p && sc_pool_live(p) == workers[w]);
    assert(sc_pool_start(p)); wait_done(p); sc_pool_release(p);
    for (int batch = 0; batch < 8; ++batch) {
      for (int i = 0; i < 4; ++i) {
        int lang = (batch * 4 + i) % 8;
        char *input = strdup(fixtures[lang]); assert(input);
        assert(sc_pool_add(p, lang, (const uint8_t *)input, (uint32_t)strlen(input)));
        /* No worker may retain this caller-owned input. */
        memset(input, '?', strlen(input)); free(input);
      }
      assert(sc_pool_start(p));
      assert(!sc_pool_start(p));
      assert(!sc_pool_add(p, 0, (const uint8_t *)"", 0));
      wait_done(p);
      for (int i = 0; i < 4; ++i) {
        int lang = (batch * 4 + i) % 8;
        check_result(p, i, lang, fixtures[lang]);
      }
      sc_pool_release(p);
    }
    assert(sc_pool_add(p, 1, (const uint8_t *)"", 0));
    assert(sc_pool_add(p, 1, (const uint8_t *)"export function {", 17));
    assert(sc_pool_start(p)); wait_done(p);
    check_result(p, 0, 1, ""); check_result(p, 1, 1, "export function {");
    sc_pool_release(p); stop_join(p);
  }
}
static void limits_and_faults(void) {
  assert(!sc_pool_new(0)); assert(!sc_pool_new(5));
  atomic_store(&alloc_fail, 0); assert(!sc_pool_new(2));
  for (int i = 0; i < 4; ++i) {
    atomic_store(&thread_fail, i); assert(!sc_pool_new(4));
  }
  SCWorkerPool *p = sc_pool_new(2); assert(p);
  atomic_store(&alloc_fail, 0);
  assert(!sc_pool_add(p, 0, (const uint8_t *)"", 0));
  for (int i = 0; i < 4; ++i) assert(sc_pool_add(p, 0, (const uint8_t *)"", 0));
  assert(!sc_pool_add(p, 0, (const uint8_t *)"", 0));
  sc_pool_release(p);
  uint8_t *large = malloc(8 * 1024 * 1024 + 1); assert(large);
  memset(large, ' ', 8 * 1024 * 1024 + 1);
  assert(!sc_pool_add(p, 0, large, 8 * 1024 * 1024 + 1));
  assert(sc_pool_add(p, 0, large, 8 * 1024 * 1024));
  assert(sc_pool_add(p, 0, large, 8 * 1024 * 1024));
  assert(!sc_pool_add(p, 0, large, 1));
  sc_pool_release(p); free(large);
  assert(sc_pool_add(p, 0, (const uint8_t *)"", 0));
  atomic_store(&alloc_fail, 0); assert(sc_pool_start(p)); wait_done(p);
  uint32_t length = 0; assert(!sc_pool_result(p, 0, &length));
  sc_pool_release(p); stop_join(p);
  SCPlan plan = sc_plan(99, "", 0, 200000); assert(plan.status == 4 && !plan.keep);
  plan = sc_plan(1, "", 8 * 1024 * 1024 + 1, 200000); assert(plan.status == 3 && !plan.keep);
  char deep[1500];
  memset(deep, '[', 600); deep[600] = '0'; memset(deep + 601, ']', 600); deep[1201] = ';';
  plan = sc_plan(1, deep, 1202, 0); assert(plan.status == 3 && !plan.keep);
  const char *statement = "const f = 123;\n";
  size_t n = strlen(statement) * 16000;
  char *slow = malloc(n); assert(slow);
  for (size_t i = 0; i < n; i += strlen(statement)) memcpy(slow + i, statement, strlen(statement));
  plan = sc_plan(1, slow, (uint32_t)n, 1); assert(plan.status == 2 && !plan.keep);
  free(slow);
}
static void global_bounds(void) {
  SCWorkerPool *p = sc_pool_new(2), *q = sc_pool_new(2);
  assert(p && q && !sc_pool_new(1));
  uint8_t *source = calloc(8 * 1024 * 1024, 1); assert(source);
  assert(sc_pool_add(p, 0, source, 8 * 1024 * 1024));
  assert(sc_pool_add(q, 0, source, 8 * 1024 * 1024));
  assert(!sc_pool_add(p, 0, source, 1));
  sc_pool_release(p);
  assert(sc_pool_add(q, 0, source, 0));
  assert(sc_pool_add(q, 0, source, 0));
  assert(sc_pool_add(p, 0, source, 0));
  assert(!sc_pool_add(p, 0, source, 0));
  free(source);
  sc_pool_release(p); sc_pool_release(q);
  stop_join(p); assert(!sc_pool_new(3)); stop_join(q);
  p = sc_pool_new(4); assert(p); stop_join(p);
}
static void cancellation(void) {
  atomic_bool cancel = true;
  SCPlan plan = sc_plan_cancelable(1, fixtures[1], (uint32_t)strlen(fixtures[1]), 200000, &cancel);
  assert(plan.status == 5 && !plan.keep);
  const char *line = "export function f() { return 123456789; }\n";
  size_t length = strlen(line), n = length * 16000;
  uint8_t *source = malloc(n); assert(source);
  for (size_t i = 0; i < n; i += length) memcpy(source + i, line, length);
  for (int workers = 1; workers <= 4; workers *= 2) {
    for (int trial = 0; trial < 4; ++trial) {
      SCWorkerPool *p = sc_pool_new(workers); assert(p);
      for (int i = 0; i < 4; ++i) assert(sc_pool_add(p, 1, source, (uint32_t)n));
      assert(sc_pool_start(p));
      // Exercise both immediate queued cancellation and in-progress parser work;
      // correctness does not depend on which phase the scheduler reached.
      if (trial & 1) pause_poll();
      stop_join(p);
    }
  }
  free(source);
}
int main(void) {
  differential(); puts("PASS: 1/2/4 workers, ordered serial masks/ranges, copied ownership, reuse, empty/error");
  limits_and_faults(); puts("PASS: source/batch/task/depth/timeout limits, allocation and partial thread creation failures");
  global_bounds(); puts("PASS: process-wide worker/task/UTF-8 budgets across simultaneous pools");
  cancellation(); puts("PASS: atomic cancellation, stop/drain/join, no live workers after cleanup");
  return 0;
}
