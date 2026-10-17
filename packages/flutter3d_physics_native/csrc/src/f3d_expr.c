/*
 * The expression language's bytecode, run in C: so the core can evaluate a
 * material's law at a body's state, and a probe's derived quantity, without
 * Dart.
 *
 * The format is flutter3d_foundation's internal one (expression_bytecode.
 * dart), version 1, and this is a port of its interpreter: little-endian,
 *
 *   header        'F3DX'  u16 version  u16 flags (0)
 *                 u16 lanes  u16 constants  u16 dimensions  u16 inputs
 *                 u16 instructions  u16 result lane  u16 result width
 *                 u16 result dimension
 *   constants     f64 × constants
 *   dimensions    (i8 × 8 exponents, u8 1 for a bool) × dimensions
 *   inputs        (u16 name length, UTF-8 name, u16 lane, u16 width,
 *                 u16 dimension) × inputs
 *   instructions  (u16 × 8: op, width | flags << 8, dst, a, b, c,
 *                 dimension, 0) × instructions
 *
 * Every instruction writes fresh lanes of doubles, so a run is a straight
 * line. **Doubles whatever f3d_real is**: the Dart interpreter computes in
 * binary64, and so does this one, in the f32 build too, so the two agree
 * to the bit on every program; a caller in f32 rounds the answer once, at
 * the end. The transcendental functions are flutter3d_foundation's
 * Portable maths (portable_math.dart), fdlibm's polynomials ported line for
 * line, never the platform's libm; floor and round are written out here,
 * since the WebAssembly build has no C library.
 *
 * Loading checks what running needs: every lane read is in range and was
 * written before it is read (an input, or an earlier instruction), every
 * constant and dimension named exists. The units the Dart side checks
 * (ExpressionBytecode.verify) are not checked again: they cannot make a
 * run read or write out of bounds.
 */
#include "f3d_internal.h"

/* ---------------------------------------------------------------- bits */

typedef union F3dBits64 {
  double d;
  uint64_t u;
} F3dBits64;

static uint64_t bits_of(double x) {
  F3dBits64 b;
  b.d = x;
  return b.u;
}

static double of_bits(uint64_t u) {
  F3dBits64 b;
  b.u = u;
  return b.d;
}

/* The top thirty-two bits: sign, exponent, high mantissa. Unsigned, as the
 * Dart reads it; arithmetic on it is done in int64_t, as Dart's int. */
static int64_t high_word(double x) { return (int64_t)(bits_of(x) >> 32); }

static int64_t low_word(double x) { return (int64_t)(bits_of(x) & 0xFFFFFFFFu); }

/* [x] with its top word replaced by the low thirty-two bits of [high], as
 * ByteData.setUint32 stores them. */
static double with_high_word(double x, int64_t high) {
  return of_bits(((uint64_t)(uint32_t)high << 32) | (bits_of(x) & 0xFFFFFFFFu));
}

static double with_low_word_zero(double x) {
  return of_bits(bits_of(x) & 0xFFFFFFFF00000000u);
}

static int is_nan(double x) { return x != x; }

static int is_infinite(double x) {
  return !is_nan(x) && is_nan(x - x);
}

static int is_finite(double x) { return x - x == 0.0; }

/* Dart's isNegative: the sign bit, so -0.0 is negative. Asked only of a
 * number that is not NaN. */
static int is_negative(double x) { return (bits_of(x) >> 63) != 0; }

/* Dart's abs: the sign bit cleared, so -0.0 is 0.0. */
static double abs_of(double x) { return of_bits(bits_of(x) & 0x7FFFFFFFFFFFFFFFu); }

/* Dart's truncateToDouble: toward nought, the sign kept (-0.3 is -0.0). */
static double truncate_of(double x) {
  if (!(abs_of(x) < 4503599627370496.0)) return x; /* 2^52: whole already */
  const double t = (double)(int64_t)x;
  return of_bits(bits_of(t) | (bits_of(x) & 0x8000000000000000u));
}

/* Dart's floorToDouble. */
static double floor_of(double x) {
  const double t = truncate_of(x);
  return t > x ? t - 1.0 : t;
}

/* Dart's roundToDouble: to the nearest, a half away from nought. */
static double round_of(double x) {
  const double t = truncate_of(x);
  const double rest = x - t;
  if (rest >= 0.5) return t + 1.0;
  if (rest <= -0.5) return t - 1.0;
  return t;
}

/* Dart's x % m for a positive m: never negative. */
static double modulo_of(double x, double m) { return x - m * floor_of(x / m); }

static double sqrt_of(double x) {
#if defined(_MSC_VER)
  return sqrt(x);
#else
  return __builtin_sqrt(x);
#endif
}

static double nan_value(void) { return of_bits(0x7FF8000000000000u); }

static double infinity_value(void) { return of_bits(0x7FF0000000000000u); }

/* ------------------------------------------------- Portable's constants */

static const double PI = 3.14159265358979311600;
static const double PIO2 = 1.57079632679489655800;
static const double PIO4 = 0.78539816339744827900;
static const double TWO_OVER_PI = 0.63661977236758134308;
static const double PIO2_HI = 1.57079632673412561417;
static const double PIO2_LO = 6.07710050650619224932e-11;

static const double SIN_S1 = -1.66666666666666324348e-01;
static const double SIN_S2 = 8.33333333332248946124e-03;
static const double SIN_S3 = -1.98412698298579493134e-04;
static const double SIN_S4 = 2.75573137070700676789e-06;
static const double SIN_S5 = -2.50507602534068634195e-08;
static const double SIN_S6 = 1.58969099521155010221e-10;

static const double COS_C1 = 4.16666666666666019037e-02;
static const double COS_C2 = -1.38888888888741095749e-03;
static const double COS_C3 = 2.48015872894767294178e-05;
static const double COS_C4 = -2.75573143513906633035e-07;
static const double COS_C5 = 2.08757232129817482790e-09;
static const double COS_C6 = -1.13596475577881948265e-11;

static const double AT0 = 3.33333333333329318027e-01;
static const double AT1 = -1.99999999998764832476e-01;
static const double AT2 = 1.42857142725034663711e-01;
static const double AT3 = -1.11111104054623557880e-01;
static const double AT4 = 9.09088713343650656196e-02;
static const double AT5 = -7.69187620504482999495e-02;
static const double AT6 = 6.66107313738753120669e-02;
static const double AT7 = -5.83357013379057348645e-02;
static const double AT8 = 4.97687799461593236017e-02;
static const double AT9 = -3.65315727442169155270e-02;
static const double AT10 = 1.62858201153657823623e-02;

static const double ATAN_HI[4] = {
    4.63647609000806093515e-01,
    7.85398163397448278999e-01,
    9.82793723247329054082e-01,
    1.57079632679489655800e+00,
};
static const double ATAN_LO[4] = {
    2.26987774529616870924e-17,
    3.06161699786838301793e-17,
    1.39033110312309984516e-17,
    6.12323399573676603587e-17,
};

static const double EXP_OVERFLOW = 709.782712893383973096;
static const double EXP_UNDERFLOW = -745.133219101941108420;
static const double LOG2E = 1.44269504088896338700;
static const double LN2_HI = 6.93147180369123816490e-01;
static const double LN2_LO = 1.90821492927058770002e-10;

static const double EXP_P1 = 1.66666666666666019037e-01;
static const double EXP_P2 = -2.77777777770155933842e-03;
static const double EXP_P3 = 6.61375632143793436117e-05;
static const double EXP_P4 = -1.65339022054652515390e-06;
static const double EXP_P5 = 4.13813679705723846039e-08;

static const double TWO54 = 1.80143985094819840000e+16;
static const double TWO53 = 9007199254740992.0;

static const double LOG_LG1 = 6.666666666666735130e-01;
static const double LOG_LG2 = 3.999999999940941908e-01;
static const double LOG_LG3 = 2.857142874366239149e-01;
static const double LOG_LG4 = 2.222219843214978396e-01;
static const double LOG_LG5 = 1.818357216161805012e-01;
static const double LOG_LG6 = 1.531383769920937332e-01;
static const double LOG_LG7 = 1.479819860511658591e-01;

static const double POW_BP[2] = {1.0, 1.5};
static const double POW_DP_HI[2] = {0.0, 5.84962487220764160156e-01};
static const double POW_DP_LO[2] = {0.0, 1.35003920212974897128e-08};
static const double POW_L1 = 5.99999999999994648725e-01;
static const double POW_L2 = 4.28571428578550184252e-01;
static const double POW_L3 = 3.33333329818377432918e-01;
static const double POW_L4 = 2.72728123808534006489e-01;
static const double POW_L5 = 2.30660745775561754067e-01;
static const double POW_L6 = 2.06975017800338417784e-01;
static const double POW_CP = 9.61796693925975554329e-01;
static const double POW_CP_HI = 9.61796700954437255859e-01;
static const double POW_CP_LO = -7.02846165095275826516e-09;
static const double LG2 = 6.93147180559945286227e-01;
static const double LG2_HI = 6.93147182464599609375e-01;
static const double LG2_LO = -1.90465429995776804525e-09;
static const double IVLN2 = 1.44269504088896338700e+00;
static const double IVLN2_HI = 1.44269502162933349609e+00;
static const double IVLN2_LO = 1.92596299112661746887e-08;
static const double POW_OVT = 8.0085662595372944372e-17;

/* ----------------------------------------------------- Portable's maths */

/* 2^k for -1021 ≤ k ≤ 1023, from its exponent field. */
static double two_to(int64_t k) { return with_high_word(0.0, (k + 1023) << 20); }

static double scale_by_power_of_two(double x, int64_t k) {
  if (k >= -1021 && k <= 1023) return x * two_to(k);
  if (k > 1023) return x * two_to(1023) * two_to(k - 1023);
  return x * two_to(-1021) * two_to(k + 1021);
}

typedef struct Reduced {
  int quadrant;
  double r, tail;
} Reduced;

static Reduced quarter_turns(double x) {
  const double n = round_of(x * TWO_OVER_PI);
  const double hi = x - n * PIO2_HI;
  const double lo = n * PIO2_LO;
  const double r = hi - lo;
  Reduced out;
  out.quadrant = (int)modulo_of(n, 4.0);
  out.r = r;
  out.tail = (hi - r) - lo;
  return out;
}

static double sin_kernel(double x, double tail) {
  const double z = x * x;
  const double v = z * x;
  const double r = SIN_S2 + z * (SIN_S3 + z * (SIN_S4 + z * (SIN_S5 + z * SIN_S6)));
  if (tail == 0.0) return x + v * (SIN_S1 + z * r);
  return x - ((z * (0.5 * tail - v * r) - tail) - v * SIN_S1);
}

static double cos_kernel(double x, double tail) {
  const double z = x * x;
  const double r =
      z * (COS_C1 +
           z * (COS_C2 + z * (COS_C3 + z * (COS_C4 + z * (COS_C5 + z * COS_C6)))));
  const double hz = 0.5 * z;
  const double w = 1.0 - hz;
  return w + (((1.0 - w) - hz) + (z * r - x * tail));
}

static double portable_sin(double x) {
  if (!is_finite(x)) return nan_value();
  const Reduced q = quarter_turns(x);
  switch (q.quadrant) {
    case 0:
      return sin_kernel(q.r, q.tail);
    case 1:
      return cos_kernel(q.r, q.tail);
    case 2:
      return -sin_kernel(q.r, q.tail);
    default:
      return -cos_kernel(q.r, q.tail);
  }
}

static double portable_cos(double x) {
  if (!is_finite(x)) return nan_value();
  const Reduced q = quarter_turns(x);
  switch (q.quadrant) {
    case 0:
      return cos_kernel(q.r, q.tail);
    case 1:
      return -sin_kernel(q.r, q.tail);
    case 2:
      return -cos_kernel(q.r, q.tail);
    default:
      return sin_kernel(q.r, q.tail);
  }
}

/* sinCos's pair, then their quotient. */
static double portable_tan(double x) {
  if (!is_finite(x)) return nan_value();
  const Reduced q = quarter_turns(x);
  const double s = sin_kernel(q.r, q.tail);
  const double c = cos_kernel(q.r, q.tail);
  switch (q.quadrant) {
    case 0:
      return s / c;
    case 1:
      return c / -s;
    case 2:
      return -s / -c;
    default:
      return -c / s;
  }
}

static double portable_atan(double x) {
  if (is_nan(x)) return nan_value();
  const int negative = is_negative(x);
  const double magnitude = abs_of(x);
  if (is_infinite(magnitude)) return negative ? -PIO2 : PIO2;
  int piece;
  double folded;
  if (magnitude < 0.4375) {
    piece = -1;
    folded = magnitude;
  } else if (magnitude < 0.6875) {
    piece = 0;
    folded = (2.0 * magnitude - 1.0) / (2.0 + magnitude);
  } else if (magnitude < 1.1875) {
    piece = 1;
    folded = (magnitude - 1.0) / (magnitude + 1.0);
  } else if (magnitude < 2.4375) {
    piece = 2;
    folded = (magnitude - 1.5) / (1.0 + 1.5 * magnitude);
  } else {
    piece = 3;
    folded = -1.0 / magnitude;
  }
  const double z = folded * folded;
  const double w = z * z;
  const double odd = z * (AT0 + w * (AT2 + w * (AT4 + w * (AT6 + w * (AT8 + w * AT10)))));
  const double even = w * (AT1 + w * (AT3 + w * (AT5 + w * (AT7 + w * AT9))));
  if (piece < 0) {
    const double result = folded - folded * (odd + even);
    return negative ? -result : result;
  }
  const double result =
      ATAN_HI[piece] - ((folded * (odd + even) - ATAN_LO[piece]) - folded);
  return negative ? -result : result;
}

static double portable_atan2(double y, double x) {
  if (is_nan(x) || is_nan(y)) return nan_value();
  if (y == 0.0) {
    if (x > 0.0 || (x == 0.0 && !is_negative(x))) return y;
    return is_negative(y) ? -PI : PI;
  }
  if (x == 0.0) return is_negative(y) ? -PIO2 : PIO2;
  if (is_infinite(x)) {
    if (is_infinite(y)) {
      const double quarter = is_negative(x) ? 3.0 * PIO4 : PIO4;
      return is_negative(y) ? -quarter : quarter;
    }
    const double flat = is_negative(x) ? PI : 0.0;
    return is_negative(y) ? -flat : flat;
  }
  if (is_infinite(y)) return is_negative(y) ? -PIO2 : PIO2;
  const double angle = portable_atan(abs_of(y / x));
  const double folded = is_negative(x) ? PI - angle : angle;
  return is_negative(y) ? -folded : folded;
}

static double portable_asin(double x) {
  if (is_nan(x) || x < -1.0 || x > 1.0) return nan_value();
  return portable_atan2(x, sqrt_of((1.0 - x) * (1.0 + x)));
}

static double portable_acos(double x) {
  if (is_nan(x) || x < -1.0 || x > 1.0) return nan_value();
  return portable_atan2(sqrt_of((1.0 - x) * (1.0 + x)), x);
}

static double portable_exp(double x) {
  if (is_nan(x)) return x;
  if (x > EXP_OVERFLOW) return infinity_value();
  if (x < EXP_UNDERFLOW) return 0.0;
  const double k = round_of(x * LOG2E);
  const double hi = x - k * LN2_HI;
  const double lo = k * LN2_LO;
  const double r = hi - lo;
  const double t = r * r;
  const double c = r - t * (EXP_P1 + t * (EXP_P2 + t * (EXP_P3 + t * (EXP_P4 + t * EXP_P5))));
  if (k == 0.0) return 1.0 - ((x * c) / (c - 2.0) - x);
  const double y = 1.0 - ((lo - (r * c) / (2.0 - c)) - hi);
  return scale_by_power_of_two(y, (int64_t)k);
}

static double portable_log(double x) {
  if (is_nan(x)) return x;
  if (x < 0.0) return nan_value();
  if (x == 0.0) return -infinity_value();
  if (is_infinite(x)) return x;
  double value = x;
  int64_t k = 0;
  int64_t hx = high_word(value);
  if (hx < 0x00100000) {
    k -= 54;
    value *= TWO54;
    hx = high_word(value);
  }
  k += (hx >> 20) - 1023;
  hx &= 0x000FFFFF;
  const int64_t carry = (hx + 0x95F64) & 0x100000;
  value = with_high_word(value, hx | (carry ^ 0x3FF00000));
  k += carry >> 20;
  const double f = value - 1.0;
  const double dk = (double)k;
  if ((0x000FFFFF & (2 + hx)) < 3) {
    if (f == 0.0) {
      if (k == 0) return 0.0;
      return dk * LN2_HI + dk * LN2_LO;
    }
    const double r = f * f * (0.5 - 0.33333333333333333 * f);
    if (k == 0) return f - r;
    return dk * LN2_HI - ((r - dk * LN2_LO) - f);
  }
  const double s = f / (2.0 + f);
  const double z = s * s;
  const double w = z * z;
  const double t1 = w * (LOG_LG2 + w * (LOG_LG4 + w * LOG_LG6));
  const double t2 = z * (LOG_LG1 + w * (LOG_LG3 + w * (LOG_LG5 + w * LOG_LG7)));
  const double r = t2 + t1;
  if (hx >= 0x6147A && hx <= 0x6B851) {
    const double hfsq = 0.5 * f * f;
    if (k == 0) return f - (hfsq - s * (hfsq + r));
    return dk * LN2_HI - ((hfsq - (s * (hfsq + r) + dk * LN2_LO)) - f);
  }
  if (k == 0) return f - s * (f - r);
  return dk * LN2_HI - ((s * (f - r) - dk * LN2_LO) - f);
}

static double portable_pow(double x, double y) {
  if (y == 0.0) return 1.0;
  if (x == 1.0) return 1.0;
  if (is_nan(x) || is_nan(y)) return nan_value();

  const double ay = abs_of(y);
  int y_is_int;
  if (is_infinite(y) || y != truncate_of(y)) {
    y_is_int = 0;
  } else if (ay >= TWO53) {
    y_is_int = 2;
  } else {
    y_is_int = modulo_of(ay, 2.0) == 1.0 ? 1 : 2;
  }
  const double ax = abs_of(x);

  if (is_infinite(y)) {
    if (ax == 1.0) return 1.0;
    if (ax > 1.0) return is_negative(y) ? 0.0 : infinity_value();
    return is_negative(y) ? infinity_value() : 0.0;
  }
  if (y == 1.0) return x;
  if (y == -1.0) return 1.0 / x;
  if (y == 2.0) return x * x;
  if (y == 0.5 && !is_negative(x)) return sqrt_of(x);

  if (ax == 0.0 || ax == 1.0 || is_infinite(ax)) {
    double z = ax;
    if (is_negative(y)) z = 1.0 / z;
    if (is_negative(x)) {
      if (ax == 1.0 && y_is_int == 0) return nan_value();
      if (y_is_int == 1) z = -z;
    }
    return z;
  }

  if (is_negative(x) && y_is_int == 0) return nan_value();
  const double s = is_negative(x) && y_is_int == 1 ? -1.0 : 1.0;

  const int64_t ix = high_word(ax);
  double t1, t2;

  if (ay > 2147483648.0) {
    if (ay > 18446744073709551616.0) {
      if (ix <= 0x3FEFFFFF) return is_negative(y) ? infinity_value() : 0.0;
      if (ix >= 0x3FF00000) return is_negative(y) ? 0.0 : infinity_value();
    }
    if (ix < 0x3FEFFFFF) return is_negative(y) ? s * infinity_value() : s * 0.0;
    if (ix > 0x3FF00000) return is_negative(y) ? s * 0.0 : s * infinity_value();
    const double t = ax - 1.0;
    const double w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25));
    const double u = IVLN2_HI * t;
    const double v = t * IVLN2_LO - w * IVLN2;
    t1 = with_low_word_zero(u + v);
    t2 = v - (t1 - u);
  } else {
    double scaled = ax;
    int64_t hi = ix;
    int64_t n = 0;
    if (hi < 0x00100000) {
      scaled *= TWO53;
      n -= 53;
      hi = high_word(scaled);
    }
    n += (hi >> 20) - 0x3FF;
    const int64_t mantissa = hi & 0x000FFFFF;
    hi = mantissa | 0x3FF00000;
    int piece;
    if (mantissa <= 0x3988E) {
      piece = 0;
    } else if (mantissa < 0xBB67A) {
      piece = 1;
    } else {
      piece = 0;
      n += 1;
      hi -= 0x00100000;
    }
    scaled = with_high_word(scaled, hi);

    const double u = scaled - POW_BP[piece];
    const double v = 1.0 / (scaled + POW_BP[piece]);
    const double ss = u * v;
    const double s_hi = with_low_word_zero(ss);
    double t_hi = with_high_word(0.0, ((hi >> 1) | 0x20000000) + 0x00080000 + ((int64_t)piece << 18));
    const double t_lo = scaled - (t_hi - POW_BP[piece]);
    const double s_lo = v * ((u - s_hi * t_hi) - s_hi * t_lo);

    double sq = ss * ss;
    double r = sq * sq *
               (POW_L1 +
                sq * (POW_L2 + sq * (POW_L3 + sq * (POW_L4 + sq * (POW_L5 + sq * POW_L6)))));
    r += s_lo * (s_hi + ss);
    sq = s_hi * s_hi;
    t_hi = with_low_word_zero(3.0 + sq + r);
    const double t_lo2 = r - ((t_hi - 3.0) - sq);

    const double u2 = s_hi * t_hi;
    const double v2 = s_lo * t_hi + t_lo2 * ss;
    const double p_hi = with_low_word_zero(u2 + v2);
    const double p_lo = v2 - (p_hi - u2);
    const double z_hi = POW_CP_HI * p_hi;
    const double z_lo = POW_CP_LO * p_hi + p_lo * POW_CP + POW_DP_LO[piece];

    const double e = (double)n;
    t1 = with_low_word_zero(((z_hi + z_lo) + POW_DP_HI[piece]) + e);
    t2 = z_lo - (((t1 - e) - POW_DP_HI[piece]) - z_hi);
  }

  const double y_hi = with_low_word_zero(y);
  const double p_lo = (y - y_hi) * t1 + y * t2;
  double p_hi = y_hi * t1;
  double z = p_lo + p_hi;
  const int64_t z_hi_word = high_word(z);
  const int64_t z_lo_word = low_word(z);
  if (!is_negative(z) && z_hi_word >= 0x40900000) {
    if (z_hi_word != 0x40900000 || z_lo_word != 0) return s * infinity_value();
    if (p_lo + POW_OVT > z - p_hi) return s * infinity_value();
  } else if ((z_hi_word & 0x7FFFFFFF) >= 0x4090CC00) {
    if (z_hi_word != 0xC090CC00 || z_lo_word != 0) return s * 0.0;
    if (p_lo <= z - p_hi) return s * 0.0;
  }

  const int64_t magnitude = z_hi_word & 0x7FFFFFFF;
  int64_t k = (magnitude >> 20) - 0x3FF;
  int64_t whole = 0;
  if (magnitude > 0x3FE00000) {
    const int64_t rounded = z_hi_word + (0x00100000 >> (k + 1));
    k = ((rounded & 0x7FFFFFFF) >> 20) - 0x3FF;
    const int64_t low = 0x000FFFFF >> k;
    const double t = with_high_word(0.0, rounded - (rounded & low));
    whole = ((rounded & 0x000FFFFF) | 0x00100000) >> (20 - k);
    if (is_negative(z)) whole = -whole;
    p_hi -= t;
  }

  double t = with_low_word_zero(p_lo + p_hi);
  const double u = t * LG2_HI;
  const double v = (p_lo - (t - p_hi)) * LG2 + t * LG2_LO;
  z = u + v;
  const double w = v - (z - u);
  t = z * z;
  const double poly = z - t * (EXP_P1 + t * (EXP_P2 + t * (EXP_P3 + t * (EXP_P4 + t * EXP_P5))));
  const double r = (z * poly) / (poly - 2.0) - (w + z * w);
  z = 1.0 - (r - z);

  const int64_t assembled = high_word(z) + whole * 0x00100000;
  if (assembled < 0x00100000) return s * scale_by_power_of_two(z, whole);
  return s * with_high_word(z, assembled);
}

/* ------------------------------------------------- the scalar kernels */

/* expression_kernels.dart, in its order of operations. */
static double mix_at(double a, double b, double t) { return a + (b - a) * t; }

static double clamp_at(double x, double low, double high) {
  return x < low ? low : (x > high ? high : x);
}

static double smoothstep_at(double edge0, double edge1, double x) {
  if (edge0 == edge1) return x < edge0 ? 0.0 : 1.0;
  const double t = clamp_at((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

static double step_at(double edge, double x) { return x < edge ? 0.0 : 1.0; }

static double min_at(double a, double b) { return a < b ? a : b; }

static double max_at(double a, double b) { return a > b ? a : b; }

static double abs_at(double x) { return x < 0.0 ? -x : x; }

static double fract_at(double x) { return x - floor_of(x); }

static double sign_at(double x) { return x > 0.0 ? 1.0 : (x < 0.0 ? -1.0 : x); }

/* ------------------------------------------------------------ the format */

enum {
  OP_LOAD_CONSTANT = 1,
  OP_MOVE = 2,
  OP_SWIZZLE = 3,
  OP_NEGATE = 4,
  OP_NOT = 5,
  OP_ADD = 6,
  OP_SUBTRACT = 7,
  OP_MULTIPLY = 8,
  OP_DIVIDE = 9,
  OP_LESS = 10,
  OP_LESS_EQUAL = 11,
  OP_GREATER = 12,
  OP_GREATER_EQUAL = 13,
  OP_EQUAL = 14,
  OP_NOT_EQUAL = 15,
  OP_AND = 16,
  OP_OR = 17,
  OP_SELECT = 18,
  OP_DOT = 20,
  OP_LENGTH = 21,
  OP_NORMALIZE = 22,
  OP_MIX = 23,
  OP_CLAMP = 24,
  OP_SMOOTHSTEP = 25,
  OP_STEP = 26,
  OP_POW = 27,
  OP_MIN = 28,
  OP_MAX = 29,
  OP_ABS = 30,
  OP_SQRT = 31,
  OP_FLOOR = 32,
  OP_FRACT = 33,
  OP_SIN = 34,
  OP_COS = 35,
  OP_TAN = 36,
  OP_ASIN = 37,
  OP_ACOS = 38,
  OP_ATAN = 39,
  OP_ATAN2 = 40,
  OP_EXP = 41,
  OP_LOG = 42,
  OP_SIGN = 43,
};

/* The bases of a dimension in version 1: kg m s A K mol cd rad. */
#define F3D_PROGRAM_BASES 8u

struct F3dProgram {
  uint16_t lanes;
  uint16_t constant_count;
  uint16_t input_count;
  uint16_t instruction_count;
  uint16_t result_lane;
  uint16_t result_width;
  double *constants;
  /* Each input's lane and width. */
  uint16_t *inputs;
  uint16_t *code;
  /* The register file, reused by every run. */
  double *registers;
};

typedef struct Reader {
  const uint8_t *at;
  uint32_t left;
  int ok;
} Reader;

static uint16_t read_u16(Reader *r) {
  if (r->left < 2) {
    r->ok = 0;
    return 0;
  }
  const uint16_t v = (uint16_t)(r->at[0] | (r->at[1] << 8));
  r->at += 2;
  r->left -= 2;
  return v;
}

static void skip(Reader *r, uint32_t count) {
  if (r->left < count) {
    r->ok = 0;
    return;
  }
  r->at += count;
  r->left -= count;
}

static double read_f64(Reader *r) {
  if (r->left < 8) {
    r->ok = 0;
    return 0.0;
  }
  uint64_t u = 0;
  for (int i = 7; i >= 0; i--) u = (u << 8) | r->at[i];
  r->at += 8;
  r->left -= 8;
  return of_bits(u);
}

void f3d_program_free(F3dProgram *program) {
  if (program == NULL) return;
  f3d_free(program->constants);
  f3d_free(program->inputs);
  f3d_free(program->code);
  f3d_free(program->registers);
  f3d_free(program);
}

/* Whether every instruction reads only lanes in range that were written
 * before it, and names only constants and dimensions that exist. */
static int program_well_formed(const F3dProgram *p, uint16_t dimensions) {
  uint8_t *written = (uint8_t *)f3d_alloc(p->lanes > 0 ? p->lanes : 1u);
  if (written == NULL) return 0;
  f3d_zero(written, p->lanes > 0 ? p->lanes : 1u);
  int ok = 1;
  for (uint32_t i = 0; ok && i < p->input_count; i++) {
    const uint32_t lane = p->inputs[2 * i], width = p->inputs[2 * i + 1];
    if (width < 1 || width > 4 || lane + width > p->lanes) {
      ok = 0;
      break;
    }
    for (uint32_t l = 0; l < width; l++) written[lane + l] = 1;
  }
  /* [count] lanes from [lane], all written. */
#define READS(lane, count)                                            \
  do {                                                                \
    const uint32_t from_ = (lane), n_ = (count);                      \
    if (from_ + n_ > p->lanes) {                                      \
      ok = 0;                                                         \
    } else {                                                          \
      for (uint32_t l_ = 0; l_ < n_; l_++) ok = ok && written[from_ + l_]; \
    }                                                                 \
  } while (0)
  for (uint32_t pc = 0; ok && pc < (uint32_t)p->instruction_count * 8u; pc += 8u) {
    const uint16_t *in = p->code + pc;
    const uint32_t op = in[0], width = in[1] & 0xFFu, flags = in[1] >> 8;
    const uint32_t dst = in[2], a = in[3], b = in[4], c = in[5], d = in[6];
    const uint32_t sa = (flags & 1u) ? 1u : width;
    const uint32_t sb = (flags & 2u) ? 1u : width;
    const uint32_t sc = (flags & 4u) ? 1u : width;
    if (width < 1 || width > 4 || d >= dimensions) {
      ok = 0;
      break;
    }
    uint32_t writes = width;
    switch (op) {
      case OP_LOAD_CONSTANT:
        if (a + width > p->constant_count) ok = 0;
        break;
      case OP_MOVE:
      case OP_NEGATE:
      case OP_ABS:
      case OP_SQRT:
      case OP_FLOOR:
      case OP_FRACT:
      case OP_SIN:
      case OP_COS:
      case OP_TAN:
      case OP_ASIN:
      case OP_ACOS:
      case OP_ATAN:
      case OP_EXP:
      case OP_LOG:
      case OP_SIGN:
      case OP_NORMALIZE:
        READS(a, width);
        break;
      case OP_LENGTH:
        READS(a, width);
        writes = 1;
        break;
      case OP_SWIZZLE: {
        uint32_t top = 0;
        for (uint32_t i = 0; i < width; i++) {
          const uint32_t s = (b >> (2 * i)) & 3u;
          if (s > top) top = s;
        }
        READS(a, top + 1);
        break;
      }
      case OP_NOT:
        READS(a, 1);
        writes = 1;
        break;
      case OP_ADD:
      case OP_SUBTRACT:
      case OP_MULTIPLY:
      case OP_DIVIDE:
      case OP_POW:
      case OP_MIN:
      case OP_MAX:
      case OP_ATAN2:
      case OP_STEP:
        READS(a, sa);
        READS(b, sb);
        break;
      case OP_LESS:
      case OP_LESS_EQUAL:
      case OP_GREATER:
      case OP_GREATER_EQUAL:
      case OP_EQUAL:
      case OP_NOT_EQUAL:
      case OP_AND:
      case OP_OR:
        READS(a, 1);
        READS(b, 1);
        writes = 1;
        break;
      case OP_SELECT:
        READS(a, 1);
        READS(b, width);
        READS(c, width);
        break;
      case OP_DOT:
        READS(a, width);
        READS(b, width);
        writes = 1;
        break;
      case OP_MIX:
      case OP_CLAMP:
      case OP_SMOOTHSTEP:
        READS(a, sa);
        READS(b, sb);
        READS(c, sc);
        break;
      default:
        ok = 0;
    }
    if (ok && dst + writes > p->lanes) ok = 0;
    for (uint32_t l = 0; ok && l < writes; l++) written[dst + l] = 1;
  }
#undef READS
  if (ok) {
    if (p->result_width < 1 || p->result_width > 4 ||
        (uint32_t)p->result_lane + p->result_width > p->lanes) {
      ok = 0;
    } else {
      for (uint32_t l = 0; l < p->result_width; l++) ok = ok && written[p->result_lane + l];
    }
  }
  f3d_free(written);
  return ok;
}

F3dProgram *f3d_program_load(const uint8_t *bytes, uint32_t length) {
  if (bytes == NULL) return NULL;
  Reader r;
  r.at = bytes;
  r.left = length;
  r.ok = 1;
  if (length < 4 || bytes[0] != 'F' || bytes[1] != '3' || bytes[2] != 'D' || bytes[3] != 'X') {
    return NULL;
  }
  skip(&r, 4);
  const uint16_t version = read_u16(&r);
  /* Every version up to this build's is read: version 1. */
  if (!r.ok || version < 1 || version > 1) return NULL;
  read_u16(&r); /* flags */
  const uint16_t lanes = read_u16(&r);
  const uint16_t constants = read_u16(&r);
  const uint16_t dimensions = read_u16(&r);
  const uint16_t inputs = read_u16(&r);
  const uint16_t instructions = read_u16(&r);
  const uint16_t result_lane = read_u16(&r);
  const uint16_t result_width = read_u16(&r);
  const uint16_t result_dimension = read_u16(&r);
  if (!r.ok || result_dimension >= dimensions) return NULL;
  F3dProgram *p = (F3dProgram *)f3d_alloc(sizeof(F3dProgram));
  if (p == NULL) return NULL;
  f3d_zero(p, sizeof *p);
  p->lanes = lanes;
  p->constant_count = constants;
  p->input_count = inputs;
  p->instruction_count = instructions;
  p->result_lane = result_lane;
  p->result_width = result_width;
  p->constants = (double *)f3d_alloc(sizeof(double) * (constants > 0 ? constants : 1u));
  p->inputs = (uint16_t *)f3d_alloc(sizeof(uint16_t) * 2u * (inputs > 0 ? inputs : 1u));
  p->code = (uint16_t *)f3d_alloc(sizeof(uint16_t) * 8u * (instructions > 0 ? instructions : 1u));
  p->registers = (double *)f3d_alloc(sizeof(double) * (lanes > 0 ? lanes : 1u));
  if (p->constants == NULL || p->inputs == NULL || p->code == NULL || p->registers == NULL) {
    f3d_program_free(p);
    return NULL;
  }
  f3d_zero(p->registers, sizeof(double) * (lanes > 0 ? lanes : 1u));
  for (uint32_t i = 0; i < constants; i++) p->constants[i] = read_f64(&r);
  skip(&r, (uint32_t)dimensions * (F3D_PROGRAM_BASES + 1u));
  for (uint32_t i = 0; i < inputs && r.ok; i++) {
    const uint16_t name = read_u16(&r);
    skip(&r, name);
    p->inputs[2 * i] = read_u16(&r);
    p->inputs[2 * i + 1] = read_u16(&r);
    read_u16(&r); /* dimension */
  }
  for (uint32_t i = 0; i < (uint32_t)instructions * 8u && r.ok; i++) p->code[i] = read_u16(&r);
  /* Nothing follows the program. */
  if (!r.ok || r.left != 0 || !program_well_formed(p, dimensions)) {
    f3d_program_free(p);
    return NULL;
  }
  return p;
}

uint32_t f3d_program_input_count(const F3dProgram *program) {
  return program != NULL ? program->input_count : 0u;
}

uint32_t f3d_program_input_width(const F3dProgram *program, uint32_t input) {
  if (program == NULL || input >= program->input_count) return 0u;
  return program->inputs[2 * input + 1];
}

uint32_t f3d_program_result_width(const F3dProgram *program) {
  return program != NULL ? program->result_width : 0u;
}

uint32_t f3d_program_run(F3dProgram *program, const double *inputs, double *out) {
  if (program == NULL || out == NULL || (inputs == NULL && program->input_count > 0)) {
    return 0u;
  }
  double *r = program->registers;
  uint32_t at = 0;
  for (uint32_t i = 0; i < program->input_count; i++) {
    const uint32_t lane = program->inputs[2 * i], width = program->inputs[2 * i + 1];
    for (uint32_t l = 0; l < width; l++) r[lane + l] = inputs[at++];
  }
  const double *k = program->constants;
  for (uint32_t pc = 0; pc < (uint32_t)program->instruction_count * 8u; pc += 8u) {
    const uint16_t *in = program->code + pc;
    const uint32_t op = in[0], width = in[1] & 0xFFu, flags = in[1] >> 8;
    const uint32_t dst = in[2], a = in[3], b = in[4], c = in[5];
    /* How far each operand moves per lane: nought when its flag spreads
     * one lane across the width. */
    const uint32_t sa = (flags & 1u) ? 0u : 1u;
    const uint32_t sb = (flags & 2u) ? 0u : 1u;
    const uint32_t sc = (flags & 4u) ? 0u : 1u;
    uint32_t i;
    switch (op) {
      case OP_LOAD_CONSTANT:
        for (i = 0; i < width; i++) r[dst + i] = k[a + i];
        break;
      case OP_MOVE:
        for (i = 0; i < width; i++) r[dst + i] = r[a + i];
        break;
      case OP_SWIZZLE: {
        double picked[4];
        for (i = 0; i < width; i++) picked[i] = r[a + ((b >> (2 * i)) & 3u)];
        for (i = 0; i < width; i++) r[dst + i] = picked[i];
        break;
      }
      case OP_NEGATE:
        for (i = 0; i < width; i++) r[dst + i] = -r[a + i];
        break;
      case OP_NOT:
        r[dst] = r[a] != 0.0 ? 0.0 : 1.0;
        break;
      case OP_ADD:
        for (i = 0; i < width; i++) r[dst + i] = r[a + i * sa] + r[b + i * sb];
        break;
      case OP_SUBTRACT:
        for (i = 0; i < width; i++) r[dst + i] = r[a + i * sa] - r[b + i * sb];
        break;
      case OP_MULTIPLY:
        for (i = 0; i < width; i++) r[dst + i] = r[a + i * sa] * r[b + i * sb];
        break;
      case OP_DIVIDE:
        for (i = 0; i < width; i++) r[dst + i] = r[a + i * sa] / r[b + i * sb];
        break;
      case OP_LESS:
        r[dst] = r[a] < r[b] ? 1.0 : 0.0;
        break;
      case OP_LESS_EQUAL:
        r[dst] = r[a] <= r[b] ? 1.0 : 0.0;
        break;
      case OP_GREATER:
        r[dst] = r[a] > r[b] ? 1.0 : 0.0;
        break;
      case OP_GREATER_EQUAL:
        r[dst] = r[a] >= r[b] ? 1.0 : 0.0;
        break;
      case OP_EQUAL:
        r[dst] = r[a] == r[b] ? 1.0 : 0.0;
        break;
      case OP_NOT_EQUAL:
        r[dst] = r[a] != r[b] ? 1.0 : 0.0;
        break;
      case OP_AND:
        r[dst] = r[a] != 0.0 && r[b] != 0.0 ? 1.0 : 0.0;
        break;
      case OP_OR:
        r[dst] = r[a] != 0.0 || r[b] != 0.0 ? 1.0 : 0.0;
        break;
      case OP_SELECT: {
        const int which = r[a] != 0.0;
        for (i = 0; i < width; i++) r[dst + i] = which ? r[b + i] : r[c + i];
        break;
      }
      case OP_DOT: {
        double sum = 0.0;
        for (i = 0; i < width; i++) sum += r[a + i] * r[b + i];
        r[dst] = sum;
        break;
      }
      case OP_LENGTH: {
        double sum = 0.0;
        for (i = 0; i < width; i++) sum += r[a + i] * r[a + i];
        r[dst] = sqrt_of(sum);
        break;
      }
      case OP_NORMALIZE: {
        double sum = 0.0;
        for (i = 0; i < width; i++) sum += r[a + i] * r[a + i];
        const double length = sqrt_of(sum);
        for (i = 0; i < width; i++) r[dst + i] = length == 0.0 ? 0.0 : r[a + i] / length;
        break;
      }
      case OP_MIX:
        for (i = 0; i < width; i++) r[dst + i] = mix_at(r[a + i * sa], r[b + i * sb], r[c + i * sc]);
        break;
      case OP_CLAMP:
        for (i = 0; i < width; i++) r[dst + i] = clamp_at(r[a + i * sa], r[b + i * sb], r[c + i * sc]);
        break;
      case OP_SMOOTHSTEP:
        for (i = 0; i < width; i++) {
          r[dst + i] = smoothstep_at(r[a + i * sa], r[b + i * sb], r[c + i * sc]);
        }
        break;
      case OP_STEP:
        for (i = 0; i < width; i++) r[dst + i] = step_at(r[a + i * sa], r[b + i * sb]);
        break;
      case OP_POW:
        for (i = 0; i < width; i++) r[dst + i] = portable_pow(r[a + i * sa], r[b + i * sb]);
        break;
      case OP_MIN:
        for (i = 0; i < width; i++) r[dst + i] = min_at(r[a + i * sa], r[b + i * sb]);
        break;
      case OP_MAX:
        for (i = 0; i < width; i++) r[dst + i] = max_at(r[a + i * sa], r[b + i * sb]);
        break;
      case OP_ATAN2:
        for (i = 0; i < width; i++) r[dst + i] = portable_atan2(r[a + i * sa], r[b + i * sb]);
        break;
      case OP_ABS:
        for (i = 0; i < width; i++) r[dst + i] = abs_at(r[a + i]);
        break;
      case OP_SQRT:
        for (i = 0; i < width; i++) r[dst + i] = sqrt_of(r[a + i]);
        break;
      case OP_FLOOR:
        for (i = 0; i < width; i++) r[dst + i] = floor_of(r[a + i]);
        break;
      case OP_FRACT:
        for (i = 0; i < width; i++) r[dst + i] = fract_at(r[a + i]);
        break;
      case OP_SIN:
        for (i = 0; i < width; i++) r[dst + i] = portable_sin(r[a + i]);
        break;
      case OP_COS:
        for (i = 0; i < width; i++) r[dst + i] = portable_cos(r[a + i]);
        break;
      case OP_TAN:
        for (i = 0; i < width; i++) r[dst + i] = portable_tan(r[a + i]);
        break;
      case OP_ASIN:
        for (i = 0; i < width; i++) r[dst + i] = portable_asin(r[a + i]);
        break;
      case OP_ACOS:
        for (i = 0; i < width; i++) r[dst + i] = portable_acos(r[a + i]);
        break;
      case OP_ATAN:
        for (i = 0; i < width; i++) r[dst + i] = portable_atan(r[a + i]);
        break;
      case OP_EXP:
        for (i = 0; i < width; i++) r[dst + i] = portable_exp(r[a + i]);
        break;
      case OP_LOG:
        for (i = 0; i < width; i++) r[dst + i] = portable_log(r[a + i]);
        break;
      case OP_SIGN:
        for (i = 0; i < width; i++) r[dst + i] = sign_at(r[a + i]);
        break;
      default:
        return 0u; /* refused when it was loaded */
    }
  }
  for (uint32_t l = 0; l < program->result_width; l++) out[l] = r[program->result_lane + l];
  return program->result_width;
}

/* ----------------------------------------------------------- the laws */

/* Whether [value] is one [property] of a material may take. */
static int law_value_ok(uint32_t property, double value) {
  if (!is_finite(value)) return 0;
  switch (property) {
    case F3D_LAW_SPECIFIC_HEAT:
    case F3D_LAW_CONDUCTIVITY:
      return value > 0.0;
    case F3D_LAW_EMISSIVITY:
      return value >= 0.0 && value <= 1.0;
    case F3D_LAW_DENSITY:
    case F3D_LAW_VISCOSITY:
    case F3D_LAW_SURFACE_TENSION:
      return value > 0.0;
    default:
      return 0;
  }
}

/* Binds [which] of [body] (water nought) or of [water] to the law [bytes]
 * hold, or takes it off for null [bytes]; the caller has checked the two
 * and the property. */
static int bind_law(F3dWorld *world, F3dBody body, F3dShallow water, uint32_t which,
                    const uint8_t *bytes, uint32_t length) {
  F3dProgram *program = NULL;
  if (bytes != NULL) {
    program = f3d_program_load(bytes, length);
    if (program == NULL) return 0;
    /* The temperature, or nothing: a law the same at every state. */
    if (program->input_count > 1 || (program->input_count == 1 && program->inputs[1] != 1) ||
        program->result_width != 1) {
      f3d_program_free(program);
      return 0;
    }
  }
  for (uint32_t i = 0; i < world->law_count; i++) {
    F3dLawBinding *law = &world->laws[i];
    if (law->body != body || law->water != water || law->property != which) continue;
    f3d_program_free(law->program);
    if (program != NULL) {
      law->program = program;
    } else {
      /* Taken off, the rest keep their order. */
      for (uint32_t j = i + 1; j < world->law_count; j++) world->laws[j - 1] = world->laws[j];
      world->law_count--;
    }
    return 1;
  }
  if (program == NULL) return 1;
  if (world->law_count == world->law_capacity) {
    const uint32_t capacity = world->law_capacity > 0 ? world->law_capacity * 2u : 8u;
    F3dLawBinding *grown =
        (F3dLawBinding *)f3d_realloc(world->laws, sizeof(F3dLawBinding) * capacity);
    if (grown == NULL) {
      f3d_program_free(program);
      return 0;
    }
    world->laws = grown;
    world->law_capacity = capacity;
  }
  F3dLawBinding *law = &world->laws[world->law_count++];
  law->body = body;
  law->water = water;
  law->property = which;
  law->program = program;
  return 1;
}

int f3d_body_set_law(F3dWorld *world, F3dBody body, F3dLawProperty property,
                     const uint8_t *bytes, uint32_t length) {
  const uint32_t which = (uint32_t)property;
  if (world == NULL || f3d_slot_of(world, body) == NULL || which > F3D_LAW_EMISSIVITY) {
    return 0;
  }
  return bind_law(world, body, 0u, which, bytes, length);
}

int f3d_shallow_set_law(F3dWorld *world, F3dShallow water, F3dLawProperty property,
                        const uint8_t *bytes, uint32_t length) {
  const uint32_t which = (uint32_t)property;
  if (world == NULL || f3d_shallow_slot(world, water) == NULL || which < F3D_LAW_DENSITY ||
      which > F3D_LAW_SURFACE_TENSION) {
    return 0;
  }
  return bind_law(world, 0u, water, which, bytes, length);
}

/* A liquid's law: its value at the liquid's temperature over what it is,
 * waking it when that changes what it is. */
static void apply_water_law(F3dWorld *world, const F3dLawBinding *law) {
  /* A water taken away keeps its law until it is taken off, as a body's
   * does; its number is never given again, so nothing is read or
   * written. */
  F3dShallowSlot *w = f3d_shallow_slot(world, law->water);
  if (w == NULL) return;
  const double temperature = (double)w->temperature;
  double value = 0.0;
  if (f3d_program_run(law->program, &temperature, &value) != 1u) return;
  if (!law_value_ok(law->property, value)) return;
  const f3d_real held = (f3d_real)value;
  f3d_real *into = law->property == F3D_LAW_DENSITY     ? &w->density
                   : law->property == F3D_LAW_VISCOSITY ? &w->viscosity
                                                        : &w->tension;
  if (*into == held) return;
  *into = held;
  /* Stepped again, as f3d_shallow_set_fluid would. */
  w->calm = F3D_R(0.0);
  w->resting = 0u;
}

void f3d_apply_laws(F3dWorld *world) {
  for (uint32_t i = 0; i < world->law_count; i++) {
    const F3dLawBinding *law = &world->laws[i];
    if (law->water != 0u) {
      apply_water_law(world, law);
      continue;
    }
    /* A body gone since keeps its law until it is taken off: its handle
     * names no slot, so nothing is read or written. */
    F3dSlot *s = f3d_slot_of(world, law->body);
    if (s == NULL) continue;
    const double temperature = (double)s->temperature;
    double value = 0.0;
    if (f3d_program_run(law->program, &temperature, &value) != 1u) continue;
    if (!law_value_ok(law->property, value)) continue;
    const f3d_real held = (f3d_real)value;
    switch (law->property) {
      case F3D_LAW_SPECIFIC_HEAT:
        s->material.specific_heat = held;
        break;
      case F3D_LAW_CONDUCTIVITY:
        s->material.conductivity = held;
        break;
      default:
        s->material.emissivity = held;
        break;
    }
  }
}

void f3d_clear_laws(F3dWorld *world) {
  for (uint32_t i = 0; i < world->law_count; i++) f3d_program_free(world->laws[i].program);
  f3d_free(world->laws);
  world->laws = NULL;
  world->law_count = 0;
  world->law_capacity = 0;
}
