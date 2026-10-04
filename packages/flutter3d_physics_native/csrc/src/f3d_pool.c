/*
 * A pool of worker threads — P9, phase 11: a world asked for more than
 * one thread hands the work it can split to these.
 *
 * Work is split the same way every time: worker w of n takes items
 * [count·w/n, count·(w+1)/n), and the calling thread is worker nought. Every
 * pass that uses the pool puts its results where they belong by item, or
 * sorts them by key afterwards, so the world steps to the same bits on one
 * thread or many.
 *
 * POSIX threads where there are some, Windows' own where there are not,
 * and none in the WebAssembly build: there the pool is never made, and
 * every pass runs on the caller.
 */
#include "f3d_internal.h"

#if defined(__wasm__)

void f3d_barrier_init(F3dBarrier *b, uint32_t workers) {
  b->arrived = 0;
  b->sense = 0;
  b->workers = workers;
}

void f3d_barrier_wait(F3dBarrier *b, uint32_t *sense) {
  (void)b;
  (void)sense;
}

F3dPool *f3d_pool_create(uint32_t threads) {
  (void)threads;
  return NULL;
}

void f3d_pool_destroy(F3dPool *pool) { (void)pool; }

#else

#if defined(_WIN32)
#include <windows.h>
typedef HANDLE Thread;
typedef SRWLOCK Lock;
typedef CONDITION_VARIABLE Signal;
#define LOCK_INIT(l) InitializeSRWLockExclusive(l)
#define LOCK(l) AcquireSRWLockExclusive(l)
#define UNLOCK(l) ReleaseSRWLockExclusive(l)
#define LOCK_FREE(l) ((void)(l))
#define SIGNAL_INIT(c) InitializeConditionVariable(c)
#define SIGNAL_WAIT(c, l) SleepConditionVariableSRW(c, l, INFINITE, 0)
#define SIGNAL_ALL(c) WakeAllConditionVariable(c)
#define SIGNAL_ONE(c) WakeConditionVariable(c)
#define SIGNAL_FREE(c) ((void)(c))
#else
#include <pthread.h>
#include <sched.h>
typedef pthread_t Thread;
typedef pthread_mutex_t Lock;
typedef pthread_cond_t Signal;
#define LOCK_INIT(l) pthread_mutex_init(l, NULL)
#define LOCK(l) pthread_mutex_lock(l)
#define UNLOCK(l) pthread_mutex_unlock(l)
#define LOCK_FREE(l) pthread_mutex_destroy(l)
#define SIGNAL_INIT(c) pthread_cond_init(c, NULL)
#define SIGNAL_WAIT(c, l) pthread_cond_wait(c, l)
#define SIGNAL_ALL(c) pthread_cond_broadcast(c)
#define SIGNAL_ONE(c) pthread_cond_signal(c)
#define SIGNAL_FREE(c) pthread_cond_destroy(c)
#endif

/* ---------------------------------------------------------------- barrier */

/* Atomics as the compilers spell them: the GCC and Clang builtins, or the
 * Interlocked functions and fences on MSVC. */
#if defined(_MSC_VER) && !defined(__clang__)
#include <intrin.h>
static uint32_t f3d_atomic_add(volatile uint32_t *p, uint32_t v) {
  return (uint32_t)_InterlockedExchangeAdd((volatile long *)p, (long)v);
}
static uint32_t f3d_atomic_load(const volatile uint32_t *p) {
  const uint32_t v = *p;
  _ReadWriteBarrier();
  return v;
}
static void f3d_atomic_store(volatile uint32_t *p, uint32_t v) {
  _ReadWriteBarrier();
  _InterlockedExchange((volatile long *)p, (long)v);
}
#else
static uint32_t f3d_atomic_add(volatile uint32_t *p, uint32_t v) {
  return __atomic_fetch_add(p, v, __ATOMIC_ACQ_REL);
}
static uint32_t f3d_atomic_load(const volatile uint32_t *p) {
  return __atomic_load_n(p, __ATOMIC_ACQUIRE);
}
static void f3d_atomic_store(volatile uint32_t *p, uint32_t v) {
  __atomic_store_n(p, v, __ATOMIC_RELEASE);
}
#endif

/* Gives the core up a moment: after spinning this long a waiter is likely
 * sharing it with a thread it waits for. */
static void yield_core(void) {
#if defined(_WIN32)
  SwitchToThread();
#else
  sched_yield();
#endif
}

void f3d_barrier_init(F3dBarrier *b, uint32_t workers) {
  b->arrived = 0;
  b->sense = 0;
  b->workers = workers;
}

void f3d_barrier_wait(F3dBarrier *b, uint32_t *sense) {
  if (b->workers < 2u) return;
  const uint32_t mine = *sense ^ 1u;
  *sense = mine;
  if (f3d_atomic_add(&b->arrived, 1u) == b->workers - 1u) {
    f3d_atomic_store(&b->arrived, 0);
    f3d_atomic_store(&b->sense, mine);
    return;
  }
  for (uint32_t spins = 0; f3d_atomic_load(&b->sense) != mine; spins++) {
    if (spins > 4096u) yield_core();
  }
}

typedef struct Worker {
  F3dPool *pool;
  uint32_t index;
  Thread thread;
} Worker;

struct F3dPool {
  uint32_t size;
  Worker *workers;
  Lock lock;
  Signal start;
  Signal done;
  /* Bumped for every pass, so a worker knows a pass from the last one. */
  uint64_t pass;
  uint32_t pending;
  int quit;
  F3dTask task;
  void *context;
  uint32_t count;
};

static void run_share(F3dPool *pool, uint32_t index, F3dTask task, void *context,
                      uint32_t count) {
  const uint32_t begin = (uint32_t)((uint64_t)count * index / pool->size);
  const uint32_t end = (uint32_t)((uint64_t)count * (index + 1u) / pool->size);
  if (begin < end) task(context, index, begin, end);
}

static void work(Worker *w) {
  F3dPool *pool = w->pool;
  uint64_t seen = 0;
  for (;;) {
    LOCK(&pool->lock);
    while (pool->pass == seen && !pool->quit) SIGNAL_WAIT(&pool->start, &pool->lock);
    if (pool->quit) {
      UNLOCK(&pool->lock);
      return;
    }
    seen = pool->pass;
    const F3dTask task = pool->task;
    void *context = pool->context;
    const uint32_t count = pool->count;
    UNLOCK(&pool->lock);
    run_share(pool, w->index, task, context, count);
    LOCK(&pool->lock);
    if (--pool->pending == 0) SIGNAL_ONE(&pool->done);
    UNLOCK(&pool->lock);
  }
}

#if defined(_WIN32)
static DWORD WINAPI thread_main(LPVOID arg) {
  work((Worker *)arg);
  return 0;
}
#else
static void *thread_main(void *arg) {
  work((Worker *)arg);
  return NULL;
}
#endif

F3dPool *f3d_pool_create(uint32_t threads) {
  if (threads < 2u || threads > F3D_MAX_THREADS) return NULL;
  F3dPool *pool = (F3dPool *)f3d_alloc(sizeof(F3dPool));
  if (pool == NULL) return NULL;
  f3d_zero(pool, sizeof *pool);
  pool->workers = (Worker *)f3d_alloc((size_t)threads * sizeof(Worker));
  if (pool->workers == NULL) {
    f3d_free(pool);
    return NULL;
  }
  pool->size = threads;
  LOCK_INIT(&pool->lock);
  SIGNAL_INIT(&pool->start);
  SIGNAL_INIT(&pool->done);
  /* Worker nought is whoever runs a pass; the rest are threads. */
  uint32_t started = 1;
  for (uint32_t i = 1; i < threads; i++) {
    Worker *w = &pool->workers[i];
    w->pool = pool;
    w->index = i;
#if defined(_WIN32)
    w->thread = CreateThread(NULL, 0, thread_main, w, 0, NULL);
    if (w->thread == NULL) break;
#else
    if (pthread_create(&w->thread, NULL, thread_main, w) != 0) break;
#endif
    started++;
  }
  if (started < threads) {
    pool->size = started;
    f3d_pool_destroy(pool);
    return NULL;
  }
  return pool;
}

void f3d_pool_destroy(F3dPool *pool) {
  if (pool == NULL) return;
  LOCK(&pool->lock);
  pool->quit = 1;
  SIGNAL_ALL(&pool->start);
  UNLOCK(&pool->lock);
  for (uint32_t i = 1; i < pool->size; i++) {
#if defined(_WIN32)
    WaitForSingleObject(pool->workers[i].thread, INFINITE);
    CloseHandle(pool->workers[i].thread);
#else
    pthread_join(pool->workers[i].thread, NULL);
#endif
  }
  SIGNAL_FREE(&pool->start);
  SIGNAL_FREE(&pool->done);
  LOCK_FREE(&pool->lock);
  f3d_free(pool->workers);
  f3d_free(pool);
}

#endif

uint32_t f3d_pool_size(const F3dPool *pool) {
#if defined(__wasm__)
  (void)pool;
  return 1u;
#else
  return pool == NULL ? 1u : pool->size;
#endif
}

void f3d_pool_run(F3dPool *pool, uint32_t count, F3dTask task, void *context) {
#if !defined(__wasm__)
  if (pool != NULL && count > 1u) {
    LOCK(&pool->lock);
    pool->task = task;
    pool->context = context;
    pool->count = count;
    pool->pending = pool->size - 1u;
    pool->pass++;
    SIGNAL_ALL(&pool->start);
    UNLOCK(&pool->lock);
    run_share(pool, 0, task, context, count);
    LOCK(&pool->lock);
    while (pool->pending > 0) SIGNAL_WAIT(&pool->done, &pool->lock);
    UNLOCK(&pool->lock);
    return;
  }
#else
  (void)pool;
#endif
  if (count > 0) task(context, 0, 0, count);
}
