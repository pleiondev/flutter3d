/// The functions a step is allowed to call, computed the same way everywhere.
///
/// ## Why this exists
///
/// `parity_test.dart` in this package asked twelve `dart:math` functions for
/// twenty thousand answers apiece on macOS-arm64, under the VM and under
/// Chrome, and digested each column. **Two matched.** `sqrt` and `pow` are the
/// two the specification pins; every transcendental — `sin`, `cos`, `tan`,
/// `asin`, `acos`, `atan`, `atan2`, `exp`, `log` — gave different bits in the
/// two places, and so did every combination of them. There is nothing portable
/// in `dart:math` to build a substitute out of, because on the VM those are the
/// host's libm and in a browser they are whatever that engine ships, and
/// neither IEEE 754 nor the Dart specification says the two agree on the last
/// bit.
///
/// `flutter3d_game_racing/test/parity_test.dart` is what that costs: the same
/// tape driving the same car diverged at twenty-three checkpoints of forty,
/// first at step 75. A character controller reached none of the disagreeing
/// arguments and matched all forty — so "a replay is the same run" was a thing
/// that happened to be true for one genre and false for another, which is the
/// worst shape a guarantee can have.
///
/// ## What is guaranteed here, and what is not
///
/// **Guaranteed: the same bits on every platform, by construction rather than
/// by luck.** Everything below is built out of `+`, `-`, `*`, `/`, `sqrt`,
/// comparison, and reading the bytes of a double — every one of which Dart
/// pins to IEEE 754 and none of which is a property of the machine. Two
/// platforms running this code cannot disagree, because there is nothing left
/// for them to disagree about. That holds for platforms nobody has measured and
/// for platforms that do not exist yet, which is the part a measurement could
/// never give.
///
/// **Not guaranteed: the last bit against `dart:math`.** These are minimax
/// polynomials with argument reduction, accurate to a couple of units in the
/// last place — not correctly rounded. `portable_math_test.dart` holds that
/// bound, because a polynomial that is quietly wrong in the fourth digit is a
/// physics bug rather than a rounding one. But a step's answers will differ
/// from the host libm's in the last bit or two, which is exactly the change
/// being made on purpose: the step stops asking the machine.
///
/// **Not a speed claim either way.** A polynomial `sin` is twenty-odd
/// arithmetic operations; a libm call is a call. Neither is the reason for
/// this.
///
/// ## Which functions are here
///
/// The seven a stepped simulation actually calls, and no more: a library with
/// an `acos` nothing calls is a library whose `acos` nobody has ever checked.
/// They arrive in five shapes — an angle turned into a direction ([sinCos]), a
/// direction turned back into an angle ([atan2]), the exponential of a damping
/// term ([exp]), the tangent in the bicycle-model steering ([tan]), and the arc
/// sine in the tyre curve ([asin]).
///
/// ## The rule that keeps it
///
/// `tool/structure.dart` holds a rule — *nothing a step runs asks the machine
/// for an answer* — that fails on `math.sin` and its neighbours anywhere in the
/// simulation. Presentation is exempt and named: a camera, a light that
/// flickers and the lightmap baker are not part of any run, and holding them to
/// this would be cost with nothing bought.
///
/// ## Where the numbers come from
///
/// The polynomial coefficients and the argument reductions are fdlibm's, which
/// is the public-domain reference every libm descends from. What is ours is
/// that they are evaluated here, in Dart, over operations that are the same
/// operations everywhere — rather than in whatever the platform linked.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The transcendental functions, computed identically on every platform.
///
/// See the library doc for why they are not `dart:math`'s.
abstract final class Portable {
  /// Sine of [radians].
  ///
  /// NaN for an argument that is not finite, as `dart:math` gives.
  static double sin(double radians) {
    if (!radians.isFinite) return double.nan;
    final reduced = _quarterTurns(radians);
    return switch (reduced.quadrant) {
      0 => _sin(reduced.r, reduced.tail),
      1 => _cos(reduced.r, reduced.tail),
      2 => -_sin(reduced.r, reduced.tail),
      _ => -_cos(reduced.r, reduced.tail),
    };
  }

  /// Cosine of [radians].
  static double cos(double radians) {
    if (!radians.isFinite) return double.nan;
    final reduced = _quarterTurns(radians);
    return switch (reduced.quadrant) {
      0 => _cos(reduced.r, reduced.tail),
      1 => -_sin(reduced.r, reduced.tail),
      2 => -_cos(reduced.r, reduced.tail),
      _ => _sin(reduced.r, reduced.tail),
    };
  }

  /// Both at once, which is the shape most call sites actually want.
  ///
  /// An angle becoming a direction needs the pair, and asking for them
  /// separately reduces the argument twice — the expensive half of the work.
  /// It is also one place rather than two for a caller to get the order wrong.
  static ({double sin, double cos}) sinCos(double radians) {
    if (!radians.isFinite) return (sin: double.nan, cos: double.nan);
    final reduced = _quarterTurns(radians);
    final s = _sin(reduced.r, reduced.tail);
    final c = _cos(reduced.r, reduced.tail);
    return switch (reduced.quadrant) {
      0 => (sin: s, cos: c),
      1 => (sin: c, cos: -s),
      2 => (sin: -s, cos: -c),
      _ => (sin: -c, cos: s),
    };
  }

  /// Tangent of [radians].
  ///
  /// **[sin] over [cos] rather than its own polynomial**, and that is a choice
  /// with a cost worth naming. A dedicated kernel is a little more accurate
  /// near the poles, where `cos` is small and the quotient magnifies its error;
  /// what this buys instead is that `tan`, `sin` and `cos` cannot disagree with
  /// each other — the same reduction and the same two kernels serve all three.
  /// The steering model that calls this works in a range nowhere near a pole.
  static double tan(double radians) {
    final both = sinCos(radians);
    return both.sin / both.cos;
  }

  /// Arc tangent of [x], in radians, between -π/2 and π/2.
  static double atan(double x) {
    if (x.isNaN) return double.nan;
    final negative = x.isNegative;
    final magnitude = x.abs();
    if (magnitude.isInfinite) return negative ? -_pio2 : _pio2;

    // Which of the four intervals the argument lands in, and the substitution
    // that folds it into the one interval the polynomial is fitted over. The
    // thresholds are fdlibm's: 7/16, 11/16, 19/16 and 39/16.
    final int piece;
    final double folded;
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

    final z = folded * folded;
    final w = z * z;
    // Split into even and odd halves so the two chains evaluate independently,
    // which is fdlibm's arrangement and is kept because the coefficients are
    // fitted to it.
    final odd =
        z *
        (_aT0 + w * (_aT2 + w * (_aT4 + w * (_aT6 + w * (_aT8 + w * _aT10)))));
    final even = w * (_aT1 + w * (_aT3 + w * (_aT5 + w * (_aT7 + w * _aT9))));

    if (piece < 0) {
      final result = folded - folded * (odd + even);
      return negative ? -result : result;
    }
    final result =
        _atanHi[piece] - ((folded * (odd + even) - _atanLo[piece]) - folded);
    return negative ? -result : result;
  }

  /// The angle of the vector ([y], [x]), in radians, between -π and π.
  ///
  /// The quadrant logic is exact arithmetic and comparison, so all of it is
  /// portable; only [atan] underneath had to be replaced.
  static double atan2(double y, double x) {
    if (x.isNaN || y.isNaN) return double.nan;
    if (y == 0.0) {
      // Sign of zero decides the side, as IEEE says it should: atan2(-0, -1)
      // is -π and atan2(+0, -1) is π.
      if (x > 0.0 || (x == 0.0 && !x.isNegative)) return y;
      return y.isNegative ? -_pi : _pi;
    }
    if (x == 0.0) return y.isNegative ? -_pio2 : _pio2;
    if (x.isInfinite) {
      if (y.isInfinite) {
        final quarter = x.isNegative ? 3.0 * _pio4 : _pio4;
        return y.isNegative ? -quarter : quarter;
      }
      final flat = x.isNegative ? _pi : 0.0;
      return y.isNegative ? -flat : flat;
    }
    if (y.isInfinite) return y.isNegative ? -_pio2 : _pio2;

    final angle = atan((y / x).abs());
    final folded = x.isNegative ? _pi - angle : angle;
    return y.isNegative ? -folded : folded;
  }

  /// Arc sine of [x], in radians. NaN outside -1 to 1.
  ///
  /// **Built on [atan2] rather than given a polynomial of its own.** The
  /// identity is `asin(x) = atan2(x, sqrt((1 - x)(1 + x)))`, and the factored
  /// form of `1 - x²` is what keeps it accurate as `|x|` approaches one, where
  /// the unfactored version loses half its digits to cancellation. At exactly
  /// ±1 the square root is zero and `atan2` answers ±π/2 without a special
  /// case. It costs a couple of units in the last place against a dedicated
  /// approximation, and it is a third of the code to be wrong in.
  ///
  /// `math.sqrt` is the one call to `dart:math` this file makes, and it is not
  /// an oversight: IEEE 754 requires the square root to be correctly rounded,
  /// and `parity_test.dart` measured that both platforms comply. It is one of
  /// the two functions there was never anything to replace.
  static double asin(double x) {
    if (x.isNaN || x < -1.0 || x > 1.0) return double.nan;
    return atan2(x, math.sqrt((1.0 - x) * (1.0 + x)));
  }

  /// e raised to [x].
  static double exp(double x) {
    if (x.isNaN) return x;
    if (x > _expOverflow) return double.infinity;
    if (x < _expUnderflow) return 0.0;

    // x = k·ln2 + r, with ln2 in two pieces so that k·ln2 is subtracted
    // exactly. |r| ends up under half a ln2, where the polynomial is fitted.
    final k = (x * _log2e).roundToDouble();
    final hi = x - k * _ln2Hi;
    final lo = k * _ln2Lo;
    final r = hi - lo;
    final t = r * r;
    final c =
        r -
        t * (_expP1 + t * (_expP2 + t * (_expP3 + t * (_expP4 + t * _expP5))));

    if (k == 0.0) return 1.0 - ((x * c) / (c - 2.0) - x);
    final y = 1.0 - ((lo - (r * c) / (2.0 - c)) - hi);
    return _scaleByPowerOfTwo(y, k.toInt());
  }

  // ## Argument reduction

  /// [x] as a quarter turn count and what is left over.
  ///
  /// `quadrant` is which multiple of π/2 was taken away, modulo four. `r` is
  /// the remainder, in -π/4 to π/4, and `tail` is the part of the remainder
  /// that did not fit in `r` — carried because the kernels below take it and
  /// because without it `cos` loses digits near a multiple of π/2.
  ///
  /// **π/2 is subtracted in two pieces, and that is the whole trick.** With one
  /// double for π/2 the product `n × π/2` is already rounded before the
  /// subtraction, so the remainder is wrong in its low bits and the wrongness
  /// grows with `n`. [_pio2Hi] has its low thirty-three bits clear, so `n ×
  /// pio2Hi` is exact for any `n` a simulation reaches, and the correction
  /// [_pio2Lo] carries the rest.
  ///
  /// The quadrant is taken with a remainder on the double rather than by
  /// converting to an integer and masking: an integer conversion of a large
  /// double is a place the VM and a browser can part company, and `n % 4.0` is
  /// exact arithmetic that cannot.
  static ({int quadrant, double r, double tail}) _quarterTurns(double x) {
    final n = (x * _twoOverPi).roundToDouble();
    final hi = x - n * _pio2Hi;
    final lo = n * _pio2Lo;
    final r = hi - lo;
    return (
      quadrant: (n % 4.0).toInt(),
      r: r,
      // Exact, because `hi` is far larger than `lo`: what the subtraction
      // rounded away is recoverable this way and no other.
      tail: (hi - r) - lo,
    );
  }

  /// Sine on -π/4 to π/4, given the remainder and its tail.
  static double _sin(double x, double tail) {
    final z = x * x;
    final v = z * x;
    final r = _sinS2 + z * (_sinS3 + z * (_sinS4 + z * (_sinS5 + z * _sinS6)));
    if (tail == 0.0) return x + v * (_sinS1 + z * r);
    return x - ((z * (0.5 * tail - v * r) - tail) - v * _sinS1);
  }

  /// Cosine on -π/4 to π/4, given the remainder and its tail.
  ///
  /// The `w` dance is not decoration: `1 - z/2` throws away the bits that the
  /// polynomial is supposed to supply, and `(1 - w) - hz` is what recovers
  /// them. Written the obvious way this loses about ten bits near ±π/4.
  static double _cos(double x, double tail) {
    final z = x * x;
    final r =
        z *
        (_cosC1 +
            z *
                (_cosC2 +
                    z * (_cosC3 + z * (_cosC4 + z * (_cosC5 + z * _cosC6)))));
    final hz = 0.5 * z;
    final w = 1.0 - hz;
    return w + (((1.0 - w) - hz) + (z * r - x * tail));
  }

  // ## Bits

  /// [x] × 2^[k], for a [k] the caller has already bounded.
  ///
  /// A multiply by a power of two is exact, so this changes the exponent and
  /// nothing else. Done in two steps when one power of two would be subnormal
  /// or infinite on its own — the answer may be either, but the multiplier may
  /// not, or the scaling would round twice.
  static double _scaleByPowerOfTwo(double x, int k) {
    if (k >= -1021 && k <= 1023) return x * _twoTo(k);
    if (k > 1023) return x * _twoTo(1023) * _twoTo(k - 1023);
    return x * _twoTo(-1021) * _twoTo(k + 1021);
  }

  /// 2^[k] as a double, for -1021 ≤ [k] ≤ 1023.
  ///
  /// Assembled from the exponent field rather than by multiplying, which would
  /// be a loop and would round. `ByteData` is the portable way to look at a
  /// double's bytes: the same eight bytes in both places, which is the property
  /// `StateDigest` leans on as well.
  static double _twoTo(int k) {
    _scratch.setUint32(0, (k + 1023) << 20);
    _scratch.setUint32(4, 0);
    return _scratch.getFloat64(0);
  }

  static final ByteData _scratch = ByteData(8);

  // ## Constants
  //
  // fdlibm's, which is where every libm's are from. The two-piece splits are
  // the part that matters: each `Hi` has its low bits clear so that a product
  // with a small whole number is exact, and each `Lo` carries what that leaves.

  static const double _pi = 3.14159265358979311600;
  static const double _pio2 = 1.57079632679489655800;
  static const double _pio4 = 0.78539816339744827900;
  static const double _twoOverPi = 0.63661977236758134308;

  /// π/2 with the low thirty-three bits of its mantissa clear.
  static const double _pio2Hi = 1.57079632673412561417;

  /// What [_pio2Hi] is missing.
  static const double _pio2Lo = 6.07710050650619224932e-11;

  static const double _sinS1 = -1.66666666666666324348e-01;
  static const double _sinS2 = 8.33333333332248946124e-03;
  static const double _sinS3 = -1.98412698298579493134e-04;
  static const double _sinS4 = 2.75573137070700676789e-06;
  static const double _sinS5 = -2.50507602534068634195e-08;
  static const double _sinS6 = 1.58969099521155010221e-10;

  static const double _cosC1 = 4.16666666666666019037e-02;
  static const double _cosC2 = -1.38888888888741095749e-03;
  static const double _cosC3 = 2.48015872894767294178e-05;
  static const double _cosC4 = -2.75573143513906633035e-07;
  static const double _cosC5 = 2.08757232129817482790e-09;
  static const double _cosC6 = -1.13596475577881948265e-11;

  static const double _aT0 = 3.33333333333329318027e-01;
  static const double _aT1 = -1.99999999998764832476e-01;
  static const double _aT2 = 1.42857142725034663711e-01;
  static const double _aT3 = -1.11111104054623557880e-01;
  static const double _aT4 = 9.09088713343650656196e-02;
  static const double _aT5 = -7.69187620504482999495e-02;
  static const double _aT6 = 6.66107313738753120669e-02;
  static const double _aT7 = -5.83357013379057348645e-02;
  static const double _aT8 = 4.97687799461593236017e-02;
  static const double _aT9 = -3.65315727442169155270e-02;
  static const double _aT10 = 1.62858201153657823623e-02;

  /// atan at the middle of each folded interval, in two pieces apiece.
  static const List<double> _atanHi = <double>[
    4.63647609000806093515e-01, // atan(0.5)
    7.85398163397448278999e-01, // atan(1.0)
    9.82793723247329054082e-01, // atan(1.5)
    1.57079632679489655800e+00, // atan(∞)
  ];
  static const List<double> _atanLo = <double>[
    2.26987774529616870924e-17,
    3.06161699786838301793e-17,
    1.39033110312309984516e-17,
    6.12323399573676603587e-17,
  ];

  /// Above this the answer is not a finite double.
  static const double _expOverflow = 709.782712893383973096;

  /// Below this it is zero, and no polynomial can say otherwise.
  static const double _expUnderflow = -745.133219101941108420;

  static const double _log2e = 1.44269504088896338700;
  static const double _ln2Hi = 6.93147180369123816490e-01;
  static const double _ln2Lo = 1.90821492927058770002e-10;

  static const double _expP1 = 1.66666666666666019037e-01;
  static const double _expP2 = -2.77777777770155933842e-03;
  static const double _expP3 = 6.61375632143793436117e-05;
  static const double _expP4 = -1.65339022054652515390e-06;
  static const double _expP5 = 4.13813679705723846039e-08;
}
