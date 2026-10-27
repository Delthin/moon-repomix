/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE.
 * Standalone private-atomic contract test; works with MSVC or C11 + pthreads. */
#include "../sc_atomic.h"
#include "../sc_atomic.h" /* include guard */
#include <assert.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <sched.h>
#endif

static SCAtomicUInt count = SC_ATOMIC_UINT_ZERO;
static SCAtomicBool start;

static void values(void) {
  SCAtomicBool flag;
  const SCAtomicBool *read_flag = &flag;
  sc_atomic_bool_init(&flag, false);
  assert(!sc_atomic_bool_load(read_flag));
  sc_atomic_bool_store(&flag, true);
  assert(sc_atomic_bool_load(read_flag));
  sc_atomic_bool_store(&flag, false);
  assert(!sc_atomic_bool_load(read_flag));
  sc_atomic_bool_init(&flag, true);
  assert(sc_atomic_bool_load(read_flag));

  assert(sc_atomic_uint_load(&count) == 0); /* static zero initialization */
  SCAtomicUInt value;
  const SCAtomicUInt *read_value = &value;
  const unsigned cases[] = {0, 1, 0x7fffffffu, 0x80000000u, UINT_MAX};
  for (unsigned i = 0; i < sizeof(cases) / sizeof(*cases); ++i) {
    unsigned original = cases[i], expected = original ^ 1u;
    sc_atomic_uint_init(&value, original);
    assert(sc_atomic_uint_load(read_value) == original);
    assert(!sc_atomic_uint_compare_exchange_weak(&value, &expected, 17));
    assert(expected == original && sc_atomic_uint_load(read_value) == original);
    while (!sc_atomic_uint_compare_exchange_weak(&value, &expected, original ^ UINT_MAX))
      assert(expected == original); /* spurious weak failure is permitted */
    assert(expected == original);
    assert(sc_atomic_uint_load(read_value) == (original ^ UINT_MAX));
    sc_atomic_uint_init(&value, original);
    assert(sc_atomic_uint_fetch_sub(&value, 1) == original);
    assert(sc_atomic_uint_load(read_value) == original - 1u);
    sc_atomic_uint_init(&value, original);
    assert(sc_atomic_uint_fetch_sub(&value, UINT_MAX) == original);
    assert(sc_atomic_uint_load(read_value) == original + 1u);
    assert(sc_atomic_uint_fetch_sub(&value, 0) == original + 1u);
  }
#ifdef _MSC_VER
  /* An atomic following a byte still satisfies the Interlocked 32-bit contract. */
  struct Embedded { char prefix; SCAtomicUInt counter; SCAtomicBool flag; } embedded;
  assert(sizeof(unsigned) == 4 && sizeof(long) == 4);
  assert(offsetof(struct Embedded, counter) % 4 == 0);
  assert(offsetof(struct Embedded, flag) % 4 == 0);
  assert((uintptr_t)&embedded.counter.value % 4 == 0);
  assert((uintptr_t)&embedded.flag.value % 4 == 0);
#endif
}
#ifdef _WIN32
static DWORD WINAPI increment(void *unused) {
#else
static void *increment(void *unused) {
#endif
  (void)unused;
  while (!sc_atomic_bool_load(&start)) {
#ifdef _WIN32
    Sleep(0);
#else
    sched_yield();
#endif
  }
  for (unsigned i = 0; i < 10000; ++i) {
    unsigned expected = sc_atomic_uint_load(&count);
    while (!sc_atomic_uint_compare_exchange_weak(&count, &expected, expected + 1u)) {}
  }
#ifdef _WIN32
  return 0;
#else
  return NULL;
#endif
}
static void contention(void) {
  sc_atomic_bool_init(&start, false);
#ifdef _WIN32
  HANDLE threads[4];
  for (int i = 0; i < 4; ++i) {
    threads[i] = CreateThread(NULL, 0, increment, NULL, 0, NULL);
    assert(threads[i]);
  }
#else
  pthread_t threads[4];
  for (int i = 0; i < 4; ++i) assert(!pthread_create(&threads[i], NULL, increment, NULL));
#endif
  sc_atomic_bool_store(&start, true);
  for (int i = 0; i < 4; ++i) {
#ifdef _WIN32
    assert(WaitForSingleObject(threads[i], INFINITE) == WAIT_OBJECT_0);
    assert(CloseHandle(threads[i]));
#else
    assert(!pthread_join(threads[i], NULL));
#endif
  }
  assert(sc_atomic_uint_load(&count) == 40000);
  assert(sc_atomic_uint_fetch_sub(&count, 40000) == 40000);
  assert(sc_atomic_uint_load(&count) == 0);
}
int main(void) {
  values(); puts("PASS: bool init/load/store, const reads, CAS expected writeback, unsigned boundaries/wrap");
  contention(); puts("PASS: four-thread CAS contention, atomic start flag, exact counter release");
  return 0;
}
