/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE. */
#ifndef MOON_REPOMIX_SC_ATOMIC_H
#define MOON_REPOMIX_SC_ATOMIC_H
#include <stdbool.h>

/* Private relaxed bool/unsigned operations, not a replacement for stdatomic.h.
 * MSVC's C11 atomics require an experimental opt-in; use its supported 32-bit
 * Interlocked intrinsics instead. Their full barriers are stronger than the
 * relaxed ordering required here. Other compilers keep the original C11 path.
 * No generic atomic names or Windows API macros are defined by this header. */
#ifdef _MSC_VER
#include <intrin.h>
#include <string.h>

typedef struct { __declspec(align(4)) long value; } SCAtomicBool;
typedef struct { __declspec(align(4)) long value; } SCAtomicUInt;
typedef char SCAtomicUIntRequires32Bits[
  sizeof(long) == 4 && sizeof(unsigned) == 4 ? 1 : -1];
#define SC_ATOMIC_UINT_ZERO {0}

/* Preserve every unsigned bit, including values above LONG_MAX, without signed
 * arithmetic overflow or an out-of-range unsigned-to-signed conversion. */
static inline long sc_atomic_uint_bits(unsigned value) {
  long bits;
  memcpy(&bits, &value, sizeof(bits));
  return bits;
}
static inline void sc_atomic_bool_init(SCAtomicBool *object, bool value) {
  object->value = value ? 1 : 0; /* initialization precedes publication */
}
static inline bool sc_atomic_bool_load(const SCAtomicBool *object) {
  /* Logical const: Interlocked needs a writable pointer even for a read.
   * These objects live in writable storage; never declare the object const. */
  return _InterlockedCompareExchange((long *)&object->value, 0, 0) != 0;
}
static inline void sc_atomic_bool_store(SCAtomicBool *object, bool value) {
  (void)_InterlockedExchange(&object->value, value ? 1 : 0);
}
static inline void sc_atomic_uint_init(SCAtomicUInt *object, unsigned value) {
  object->value = sc_atomic_uint_bits(value);
}
static inline unsigned sc_atomic_uint_load(const SCAtomicUInt *object) {
  return (unsigned)_InterlockedCompareExchange((long *)&object->value, 0, 0);
}
static inline unsigned sc_atomic_uint_fetch_sub(SCAtomicUInt *object, unsigned amount) {
  return (unsigned)_InterlockedExchangeAdd(&object->value, sc_atomic_uint_bits(0u - amount));
}
static inline bool sc_atomic_uint_compare_exchange_weak(SCAtomicUInt *object,
                                                       unsigned *expected, unsigned desired) {
  unsigned actual = (unsigned)_InterlockedCompareExchange(
    &object->value, sc_atomic_uint_bits(desired), sc_atomic_uint_bits(*expected));
  if (actual == *expected) return true;
  *expected = actual;
  return false; /* strong CAS is also a valid weak CAS; failure updates expected */
}
#else
#include <stdatomic.h>

typedef atomic_bool SCAtomicBool;
typedef atomic_uint SCAtomicUInt;
#define SC_ATOMIC_UINT_ZERO 0

static inline void sc_atomic_bool_init(SCAtomicBool *object, bool value) {
  atomic_init(object, value);
}
static inline bool sc_atomic_bool_load(const SCAtomicBool *object) {
  return atomic_load_explicit(object, memory_order_relaxed);
}
static inline void sc_atomic_bool_store(SCAtomicBool *object, bool value) {
  atomic_store_explicit(object, value, memory_order_relaxed);
}
static inline void sc_atomic_uint_init(SCAtomicUInt *object, unsigned value) {
  atomic_init(object, value);
}
static inline unsigned sc_atomic_uint_load(const SCAtomicUInt *object) {
  return atomic_load_explicit(object, memory_order_relaxed);
}
static inline unsigned sc_atomic_uint_fetch_sub(SCAtomicUInt *object, unsigned amount) {
  return atomic_fetch_sub_explicit(object, amount, memory_order_relaxed);
}
static inline bool sc_atomic_uint_compare_exchange_weak(SCAtomicUInt *object,
                                                       unsigned *expected, unsigned desired) {
  return atomic_compare_exchange_weak_explicit(object, expected, desired,
                                              memory_order_relaxed, memory_order_relaxed);
}
#endif
#endif
