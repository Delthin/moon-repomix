/* Copyright (c) 2026 moon-repomix contributors. MIT licensed; see LICENSE.
 * Forced include for the pool test object only, never the product build. */
#include <stdlib.h>
#include <pthread.h>
void *sc_test_malloc(size_t);
void *sc_test_calloc(size_t, size_t);
int sc_test_pthread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
