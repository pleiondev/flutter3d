/*
 * What every C test shares: the check counter and values a test cannot
 * write as literals. Built in both precisions by test/c_unit_test.dart.
 */
#ifndef F3D_CHECK_H_
#define F3D_CHECK_H_

#include <stdio.h>

#include "f3d_internal.h"
#include "f3d_physics.h"

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                     \
  do {                                                                  \
    g_checks++;                                                         \
    if (!(cond)) {                                                      \
      g_failures++;                                                     \
      fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__, __LINE__,  \
              #cond);                                                   \
    }                                                                   \
  } while (0)

/* |a − b| no more than [tolerance] times the larger of |b| and one. */
#define CHECK_NEAR(a, b, tolerance)                                       \
  do {                                                                    \
    const double check_a_ = (double)(a), check_b_ = (double)(b);          \
    const double check_scale_ =                                           \
        check_b_ < 0 ? (-check_b_ > 1 ? -check_b_ : 1)                    \
                     : (check_b_ > 1 ? check_b_ : 1);                     \
    const double check_d_ = check_a_ - check_b_;                          \
    g_checks++;                                                           \
    if (!((check_d_ < 0 ? -check_d_ : check_d_) <=                        \
          (tolerance) * check_scale_)) {                                  \
      g_failures++;                                                       \
      fprintf(stderr, "%s:%d: %s = %.9g, wanted %s = %.9g\n", __FILE__,   \
              __LINE__, #a, check_a_, #b, check_b_);                      \
    }                                                                     \
  } while (0)

static inline f3d_real nan_value(void) {
  volatile f3d_real zero = 0;
  return zero / zero;
}

static inline f3d_real inf_value(void) {
  volatile f3d_real zero = 0;
  return 1 / zero;
}

static inline int finish(void) {
  if (g_failures != 0) {
    fprintf(stderr, "%d of %d checks failed\n", g_failures, g_checks);
    return 1;
  }
  printf("%d checks passed\n", g_checks);
  return 0;
}

#endif /* F3D_CHECK_H_ */
