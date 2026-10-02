/// The trigonometry a rigid body step is allowed to call.
///
/// ## Why not `dart:math`
///
/// `dart:math`'s `sin`, `cos`, `atan2` and `acos` are the host's libm on the VM
/// and whatever a browser ships on the web, and neither IEEE 754 nor the Dart
/// specification says two of them agree on the last bit. `flutter3d_sim`
/// measured it: twenty thousand arguments, every transcendental answering
/// differently under the VM and under Chrome, and a car replayed from the same
/// tape diverging at twenty-three checkpoints of forty. A body that turns is
/// made of exactly these functions — a hinge's angle is an `atan2`, a cone
/// limit is an `acos` — so the step that turns one has to ask something that
/// cannot disagree with itself. `sqrt` stays `dart:math`'s: IEEE 754 requires
/// it to be correctly rounded, so there is one right answer and every platform
/// gives it.
///
/// ## Why a second copy rather than `flutter3d_sim`'s
///
/// **The arrow points the other way.** `flutter3d_sim` depends on this package,
/// so this package cannot import its `Portable`. The kernels below are the same
/// fdlibm polynomials and the same argument reduction, transcribed rather than
/// re-derived, so the two answer the same bits for the same argument —
/// `portable_math_test.dart` records digests that hold that.
///
/// **Not exported.** `flutter3d_sim` re-exports this library whole beside its
/// own `Portable`, and two public classes of one name in one export is an
/// error for every caller of the simulation. Nothing outside the step needs
/// these; a game that wants portable trigonometry already has the fuller set.
///
/// **Only what a body needs.** Sine and cosine to turn an angle into an axis,
/// and the inverses to turn a pair of axes back into an angle. No `exp`, no
/// `log`, no `pow`: damping here is a rational factor and nothing else in a
/// step raises anything to a power. A function added later belongs in this
/// file, and the rule in `tool/structure.dart` that refuses `math.sin` in a
/// step is what sends it here.
///
/// ## What is guaranteed
///
/// **The same bits everywhere, by construction.** Everything below is `+`,
/// `-`, `*`, `/`, `sqrt` and comparison, which the specification pins. **Not
/// the last bit of `dart:math`**: these are minimax polynomials, within two
/// units in the last place of the libm answer and held there by the test.
library;

import 'dart:math' as math;

/// Sine, cosine and their inverses, computed identically on every platform.
abstract final class Portable {
  /// Sine of [radians]. NaN for an argument that is not finite.
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

  /// Cosine of [radians]. NaN for an argument that is not finite.
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

  /// Both at once, which is what an angle becoming an axis wants.
  ///
  /// The argument reduction is the expensive half of either function, and this
  /// does it once.
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

  /// Arc tangent of [x], in radians, between -π/2 and π/2.
  static double atan(double x) {
    if (x.isNaN) return double.nan;
    final negative = x.isNegative;
    final magnitude = x.abs();
    if (magnitude.isInfinite) return negative ? -_pio2 : _pio2;

    // Which of fdlibm's four intervals the argument lands in (split at 7/16,
    // 11/16, 19/16 and 39/16), and the substitution that folds it onto the
    // one the polynomial is fitted over.
    final (piece, folded) = switch (magnitude) {
      < 0.4375 => (-1, magnitude),
      < 0.6875 => (0, (2.0 * magnitude - 1.0) / (2.0 + magnitude)),
      < 1.1875 => (1, (magnitude - 1.0) / (magnitude + 1.0)),
      < 2.4375 => (2, (magnitude - 1.5) / (1.0 + 1.5 * magnitude)),
      _ => (3, -1.0 / magnitude),
    };

    final z = folded * folded;
    final w = z * z;
    // Even and odd halves evaluated apart, as fdlibm does: the coefficients
    // are fitted to that arrangement.
    final odd =
        z *
        (_aT0 + w * (_aT2 + w * (_aT4 + w * (_aT6 + w * (_aT8 + w * _aT10)))));
    final even = w * (_aT1 + w * (_aT3 + w * (_aT5 + w * (_aT7 + w * _aT9))));

    final result = piece < 0
        ? folded - folded * (odd + even)
        : _atanHi[piece] - ((folded * (odd + even) - _atanLo[piece]) - folded);
    return negative ? -result : result;
  }

  /// The angle of the vector ([y], [x]), in radians, between -π and π.
  ///
  /// The quadrant logic is comparison and exact arithmetic; only [atan] under
  /// it had to be replaced.
  static double atan2(double y, double x) {
    if (x.isNaN || y.isNaN) return double.nan;
    if (y == 0.0) {
      // The sign of zero decides the side, as IEEE says: atan2(-0, -1) is -π.
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
  /// `atan2(x, sqrt((1 - x)(1 + x)))`: the factored `1 - x²` is what keeps the
  /// digits as `|x|` reaches one, where the plain square loses half of them.
  static double asin(double x) {
    if (x.isNaN || x < -1.0 || x > 1.0) return double.nan;
    return atan2(x, math.sqrt((1.0 - x) * (1.0 + x)));
  }

  /// Arc cosine of [x], in radians, between 0 and π. NaN outside -1 to 1.
  ///
  /// **Not `π/2 - asin(x)`.** Near `x = 1` the answer is nearly nothing and
  /// that subtraction is between two numbers near π/2, so it cancels most of
  /// the digits the answer was meant to have — which is the angle a joint at
  /// rest sits at. The two arguments of [atan2] swapped is two units in the
  /// last place across the whole domain.
  static double acos(double x) {
    if (x.isNaN || x < -1.0 || x > 1.0) return double.nan;
    return atan2(math.sqrt((1.0 - x) * (1.0 + x)), x);
  }

  /// [x] as a count of quarter turns, modulo four, and what is left over.
  ///
  /// **π/2 is taken away in two pieces.** [_pio2Hi] has its low thirty-three
  /// bits clear, so `n × pio2Hi` is exact for any `n` a step reaches, and
  /// [_pio2Lo] carries the rest; with one double the product rounds before the
  /// subtraction and the remainder is wrong in a way that grows with `n`. The
  /// quadrant comes from `n % 4.0`, exact arithmetic on the double, rather than
  /// from masking an integer conversion, which is where the VM and a browser
  /// part company.
  static ({int quadrant, double r, double tail}) _quarterTurns(double x) {
    final n = (x * _twoOverPi).roundToDouble();
    final hi = x - n * _pio2Hi;
    final lo = n * _pio2Lo;
    final r = hi - lo;
    return (quadrant: (n % 4.0).toInt(), r: r, tail: (hi - r) - lo);
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
  /// `(1 - w) - hz` recovers the bits `1 - z/2` throws away; written the
  /// obvious way this loses about ten of them near ±π/4.
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

  // fdlibm's constants, digit for digit the ones `flutter3d_sim` uses.

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
}
