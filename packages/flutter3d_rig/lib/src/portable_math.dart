/// The one transcendental a rig step needs, computed the same way everywhere.
///
/// ## Why this exists
///
/// `tool/structure.dart` holds a rule — *nothing a step runs asks the machine
/// for an answer* — because `math.acos` is the platform's libm on the VM and
/// whatever a browser ships in Chrome, and the two do not agree on the last
/// bit. `two_bone_ik.dart` runs inside `retarget.dart`'s `lockFeet`, which is
/// a step a replay depends on producing the same bits everywhere it runs, so
/// its `math.acos` calls have to go.
///
/// `flutter3d_sim/lib/src/math/portable_math.dart` already solved this for
/// the simulation package, with a `Portable` class covering ten functions
/// built out of `+`, `-`, `*`, `/`, `sqrt` and reading a double's bits — every
/// one of which IEEE 754 pins, unlike the transcendentals themselves. This
/// package does not depend on `flutter3d_sim` (a much heavier, higher-level
/// game-simulation package sitting in a later publishing tier than
/// `flutter3d_rig`, per `ARCHITECTURE.md`), and gaining that dependency for
/// one function would point the wrong way through the graph. `two_bone_ik.dart`
/// is the only file in this package that needs a portable transcendental, so
/// rather than inventing a shared package for one function, or reaching past
/// `flutter3d_rig`'s own tier for it, this file carries a standalone copy of
/// exactly the slice `acos` needs — `atan`, `atan2` and `acos` themselves,
/// unchanged from `flutter3d_sim`'s implementation so the two packages cannot
/// disagree with each other, either.
///
/// **Not guaranteed: the last bit against `dart:math`.** These are minimax
/// polynomials with argument reduction, accurate to a couple of units in the
/// last place — not correctly rounded. That is `flutter3d_sim`'s
/// `portable_math_test.dart` bound, inherited here because the algorithm is
/// identical; `two_bone_ik.dart`'s own callers clamp their cosine to [-1, 1]
/// first and only ever compare the result against a centimetre-scale
/// tolerance, so a couple of units in the last place is far below anything
/// that test suite watches.
///
/// The polynomial coefficients and argument reductions are fdlibm's, the
/// public-domain reference every libm descends from — see
/// `flutter3d_sim/lib/src/math/portable_math.dart` for the full derivation
/// and the measurement that motivated it.
library;

import 'dart:math' as math;

/// `acos`, computed identically to `flutter3d_sim`'s `Portable.acos`.
///
/// See the library doc for why this package carries its own copy rather than
/// depending on `flutter3d_sim` for it.
abstract final class Portable {
  /// Arc cosine of [x], in radians, between 0 and π. NaN outside -1 to 1.
  ///
  /// Built on [_atan2] rather than a polynomial of its own: the identity is
  /// `acos(x) = atan2(sqrt((1 - x)(1 + x)), x)`, and the factored form of
  /// `1 - x²` keeps it accurate as `|x|` approaches one, where the unfactored
  /// version loses digits to cancellation. `math.sqrt` is the one call to
  /// `dart:math` this makes, and it is not an oversight — IEEE 754 requires a
  /// correctly rounded square root, so every platform is obliged to agree on
  /// it already.
  static double acos(double x) {
    if (x.isNaN || x < -1.0 || x > 1.0) return double.nan;
    return _atan2(math.sqrt((1.0 - x) * (1.0 + x)), x);
  }

  /// The angle of the vector ([y], [x]), in radians, between -π and π.
  static double _atan2(double y, double x) {
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

    final angle = _atan((y / x).abs());
    final folded = x.isNegative ? _pi - angle : angle;
    return y.isNegative ? -folded : folded;
  }

  /// Arc tangent of [x], in radians, between -π/2 and π/2.
  static double _atan(double x) {
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

  static const double _pi = 3.14159265358979311600;
  static const double _pio2 = 1.57079632679489655800;
  static const double _pio4 = 0.78539816339744827900;

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
