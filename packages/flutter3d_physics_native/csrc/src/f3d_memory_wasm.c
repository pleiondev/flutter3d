/*
 * Memory for the WebAssembly build, which has no C library — P9.
 *
 * A first-fit free list over linear memory grown a page at a time. Every
 * block has a header holding its size; a freed block goes back on the list
 * and is split when a smaller request fits it, merged with nothing. That is
 * enough for a physics world, which allocates a few growing arrays and
 * frees them when the world goes, and it keeps the module free of every
 * import: the page count and the bytes are all it touches.
 *
 * memset and memcpy are here too, because clang emits calls to them for
 * struct copies and zeroing whatever the source says.
 *
 * In the threads build (F3D_WASM_THREADS) the workers allocate too — a
 * worker's lane of pairs grows in the middle of a step — so the list is
 * held by a spin lock.
 */
#ifdef __wasm__

#include "f3d_internal.h"

#define F3D_PAGE 65536u
#define F3D_ALIGN 16u

typedef struct Block {
  size_t size; /* Bytes after the header. */
  struct Block *next_free;
} Block;

#define HEADER ((sizeof(Block) + F3D_ALIGN - 1) & ~(size_t)(F3D_ALIGN - 1))

extern unsigned char __heap_base;

static unsigned char *g_top;
static unsigned char *g_end;
static Block *g_free;

void *memset(void *dst, int value, size_t n) {
  unsigned char *d = (unsigned char *)dst;
  for (size_t i = 0; i < n; i++) d[i] = (unsigned char)value;
  return dst;
}

void *memcpy(void *dst, const void *src, size_t n) {
  unsigned char *d = (unsigned char *)dst;
  const unsigned char *s = (const unsigned char *)src;
  for (size_t i = 0; i < n; i++) d[i] = s[i];
  return dst;
}

static size_t round_up(size_t bytes) {
  return (bytes + F3D_ALIGN - 1) & ~(size_t)(F3D_ALIGN - 1);
}

/* Grows linear memory until [bytes] more fit above the top. */
static int reserve(size_t bytes) {
  if (g_top == NULL) {
    g_top = (unsigned char *)round_up((size_t)&__heap_base);
    g_end = (unsigned char *)(__builtin_wasm_memory_size(0) * F3D_PAGE);
  }
  while ((size_t)(g_end - g_top) < bytes) {
    if (__builtin_wasm_memory_grow(0, 1) == (size_t)-1) return 0;
    g_end += F3D_PAGE;
  }
  return 1;
}

#ifdef F3D_WASM_THREADS
static volatile int g_lock;

static void lock(void) {
  while (__atomic_exchange_n(&g_lock, 1, __ATOMIC_ACQUIRE) != 0) {
  }
}

static void unlock(void) { __atomic_store_n(&g_lock, 0, __ATOMIC_RELEASE); }
#else
static void lock(void) {}
static void unlock(void) {}
#endif

static void *alloc_held(size_t bytes) {
  const size_t size = round_up(bytes == 0 ? 1 : bytes);
  Block **link = &g_free;
  for (Block *b = g_free; b != NULL; link = &b->next_free, b = b->next_free) {
    if (b->size < size) continue;
    *link = b->next_free;
    if (b->size >= size + HEADER + F3D_ALIGN) {
      /* Split: the rest goes back on the list as a block of its own. */
      Block *rest = (Block *)((unsigned char *)b + HEADER + size);
      rest->size = b->size - size - HEADER;
      rest->next_free = g_free;
      g_free = rest;
      b->size = size;
    }
    return (unsigned char *)b + HEADER;
  }
  if (!reserve(HEADER + size)) return NULL;
  Block *b = (Block *)g_top;
  b->size = size;
  b->next_free = NULL;
  g_top += HEADER + size;
  return (unsigned char *)b + HEADER;
}

static void free_held(void *block) {
  if (block == NULL) return;
  Block *b = (Block *)((unsigned char *)block - HEADER);
  b->next_free = g_free;
  g_free = b;
}

void *f3d_alloc(size_t bytes) {
  lock();
  void *block = alloc_held(bytes);
  unlock();
  return block;
}

void f3d_free(void *block) {
  lock();
  free_held(block);
  unlock();
}

void *f3d_realloc(void *block, size_t bytes) {
  if (block == NULL) return f3d_alloc(bytes);
  Block *b = (Block *)((unsigned char *)block - HEADER);
  if (b->size >= bytes) return block;
  lock();
  void *grown = alloc_held(bytes);
  if (grown != NULL) {
    memcpy(grown, block, b->size);
    free_held(block);
  }
  unlock();
  return grown;
}

void f3d_zero(void *block, size_t bytes) { memset(block, 0, bytes); }

void f3d_copy(void *to, const void *from, size_t bytes) {
  memcpy(to, from, bytes);
}

#else
/* Not this build; ISO C wants the file to declare something. */
typedef int f3d_memory_wasm_not_this_build;
#endif
