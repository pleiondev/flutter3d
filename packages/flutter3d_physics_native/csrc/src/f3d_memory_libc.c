/*
 * Memory through the C library, for every build but WebAssembly's —
 * f3d_memory_wasm.c is that one's.
 */
#ifndef __wasm__

#include <stdlib.h>
#include <string.h>

#include "f3d_internal.h"

void *f3d_alloc(size_t bytes) { return malloc(bytes); }

void *f3d_realloc(void *block, size_t bytes) { return realloc(block, bytes); }

void f3d_free(void *block) { free(block); }

void f3d_zero(void *block, size_t bytes) { memset(block, 0, bytes); }

void f3d_copy(void *to, const void *from, size_t bytes) {
  memcpy(to, from, bytes);
}

#else
/* Not this build; ISO C wants the file to declare something. */
typedef int f3d_memory_libc_not_this_build;
#endif
