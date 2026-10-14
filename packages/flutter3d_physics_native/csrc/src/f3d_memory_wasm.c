/*
 * Memory for the WebAssembly build, which has no C library — P9.
 *
 * A first-fit free list over linear memory grown a page at a time, kept in
 * address order. Every block has a header holding its size; a freed block
 * goes back on the list in its place and is merged with a free neighbour on
 * either side, and one that ends at the top of what was handed out lowers
 * the top instead. It keeps the module free of every import: the page count
 * and the bytes are all it touches.
 *
 * **The merging is not optional.** A world does not only allocate a few
 * arrays and free them when it goes: shallow water and the particle liquid
 * take their scratch for a step and give it back at the end of it, every
 * step, in sizes that differ from step to step and from one water to the
 * next. A list that only ever split blocks cut that memory into pieces too
 * small for the next step's requests; each step then scanned every piece
 * before growing memory past them, so the scan and the heap grew without
 * end — River Sortie's water reached a gigabyte and a second's work for two
 * seconds of play inside a few minutes, in the browser alone, since the
 * native build has the C library's allocator. wasm_test holds the heap of
 * a stepping world still.
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

/* The first byte past [b]: its neighbour's header, or the top. */
static unsigned char *end_of(Block *b) {
  return (unsigned char *)b + HEADER + b->size;
}

static void *alloc_held(size_t bytes) {
  const size_t size = round_up(bytes == 0 ? 1 : bytes);
  Block **link = &g_free;
  for (Block *b = g_free; b != NULL; link = &b->next_free, b = b->next_free) {
    if (b->size < size) continue;
    if (b->size >= size + HEADER + F3D_ALIGN) {
      /* Split: the rest stays on the list in b's place, which keeps the
       * list in address order since the rest is above b. */
      Block *rest = (Block *)((unsigned char *)b + HEADER + size);
      rest->size = b->size - size - HEADER;
      rest->next_free = b->next_free;
      *link = rest;
      b->size = size;
    } else {
      *link = b->next_free;
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
  /* Its place in the list: after every free block below it. */
  Block *prev = NULL;
  Block *next = g_free;
  while (next != NULL && next < b) {
    prev = next;
    next = next->next_free;
  }
  /* Merged with the free block above it, then with the one below. */
  if (next != NULL && end_of(b) == (unsigned char *)next) {
    b->size += HEADER + next->size;
    next = next->next_free;
  }
  if (prev != NULL && end_of(prev) == (unsigned char *)b) {
    prev->size += HEADER + b->size;
    b = prev;
  } else if (prev != NULL) {
    prev->next_free = b;
  } else {
    g_free = b;
  }
  b->next_free = next;
  /* The highest block handed out, back: the top comes down to it, so the
   * next request larger than every free block grows from there and not
   * from above it. Being the highest, it is the last on the list. */
  if (end_of(b) == g_top) {
    g_top = (unsigned char *)b;
    if (prev == b) {
      /* It merged into prev, which is still linked from below. */
      Block **link = &g_free;
      while (*link != b) link = &(*link)->next_free;
      *link = NULL;
    } else if (prev != NULL) {
      prev->next_free = NULL;
    } else {
      g_free = NULL;
    }
  }
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
