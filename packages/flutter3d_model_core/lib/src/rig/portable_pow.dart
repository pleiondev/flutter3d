/// A portable `x^y` for `bind_weights.dart`'s own narrow case: `x` is always
/// a distance plus a small positive epsilon (never zero, never negative) and
/// `y` is a falloff exponent a caller picks, typically `2.0`.
///
/// ## Why this exists
///
/// The same `tool/structure.dart` rule `two_bone_ik.dart`'s own
/// `portable_math.dart` answers for `acos` also flags `math.pow` in
/// `bind_weights.dart`: the VM's libm and a browser's do not agree on the
/// last bit, and a bind is a step a saved project's own re-bind depends on
/// reproducing everywhere it runs.
///
/// **Not fdlibm's own `pow`.** `flutter3d_sim/lib/src/math/portable_math.dart`
/// carries the real one — its own doc comment explains why `exp(y · log x)`
/// is the wrong answer in general: the logarithm's last two bits get
/// magnified by `y` before the exponential sees them, which that file
/// measured at up to seventy-nine units in the last place at `y = 5`, against
/// fdlibm's own two-unit bound. That bound matters when `pow` feeds a solver
/// that keeps its own error budget. `bindWeights` does not: [powPositive]'s
/// result only ever feeds an inverse-distance weight that is renormalised to
/// sum to one over as many as four influences, so even the worst case above
/// — a relative error near `1e-14` — is many orders below the geometric
/// approximation binding already makes (a segment's own closest point, a
/// visibility test through a BVH). Carrying fdlibm's two-hundred-line general
/// `pow` into this package for a difference nothing here can see is not a
/// trade this file makes; `exp(y · log x)`, both pieces copied unchanged from
/// `flutter3d_sim`, is.
///
/// **`x` must be positive.** [powPositive] is not a general replacement for
/// `math.pow` — it has no branch for a negative or zero base, an infinite or
/// NaN exponent, or any of `pow`'s own edge-value conventions, because
/// `bindWeights`' own call site never produces any of them (a segment
/// distance plus [epsilon] in `bindWeights` is always strictly positive).
/// Asking it for anything else answers NaN rather than guessing.
library;

import 'dart:typed_data';

/// `exp` and `log`, computed identically to `flutter3d_sim`'s
/// `Portable.exp`/`Portable.log` — see the library doc for why this package
/// carries its own copy rather than depending on `flutter3d_sim` for it, the
/// same reason `portable_math.dart`'s own `Portable` does.
abstract final class _Portable {
  static double exp(double x) {
    if (x.isNaN) return x;
    if (x > _expOverflow) return double.infinity;
    if (x < _expUnderflow) return 0.0;

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

  static double log(double x) {
    if (x.isNaN) return x;
    if (x < 0.0) return double.nan;
    if (x == 0.0) return double.negativeInfinity;
    if (x.isInfinite) return x;

    var value = x;
    var k = 0;
    var hx = _highWord(value);
    if (hx < 0x00100000) {
      k -= 54;
      value *= _two54;
      hx = _highWord(value);
    }
    k += (hx >> 20) - 1023;
    hx &= 0x000FFFFF;
    final carry = (hx + 0x95F64) & 0x100000;
    value = _withHighWord(value, hx | (carry ^ 0x3FF00000));
    k += carry >> 20;

    final f = value - 1.0;
    final dk = k.toDouble();
    if ((0x000FFFFF & (2 + hx)) < 3) {
      if (f == 0.0) {
        if (k == 0) return 0.0;
        return dk * _ln2Hi + dk * _ln2Lo;
      }
      final r = f * f * (0.5 - 0.33333333333333333 * f);
      if (k == 0) return f - r;
      return dk * _ln2Hi - ((r - dk * _ln2Lo) - f);
    }

    final s = f / (2.0 + f);
    final z = s * s;
    final w = z * z;
    final t1 = w * (_logLg2 + w * (_logLg4 + w * _logLg6));
    final t2 = z * (_logLg1 + w * (_logLg3 + w * (_logLg5 + w * _logLg7)));
    final r = t2 + t1;

    if (hx >= 0x6147A && hx <= 0x6B851) {
      final hfsq = 0.5 * f * f;
      if (k == 0) return f - (hfsq - s * (hfsq + r));
      return dk * _ln2Hi - ((hfsq - (s * (hfsq + r) + dk * _ln2Lo)) - f);
    }
    if (k == 0) return f - s * (f - r);
    return dk * _ln2Hi - ((s * (f - r) - dk * _ln2Lo) - f);
  }

  static double _scaleByPowerOfTwo(double x, int k) {
    if (k >= -1021 && k <= 1023) return x * _twoTo(k);
    if (k > 1023) return x * _twoTo(1023) * _twoTo(k - 1023);
    return x * _twoTo(-1021) * _twoTo(k + 1021);
  }

  /// 2^[k] as a double, for -1021 ≤ [k] ≤ 1023 — assembled from the exponent
  /// field rather than by multiplying, unchanged from `flutter3d_sim`'s copy.
  static double _twoTo(int k) {
    _scratch.setUint32(0, (k + 1023) << 20);
    _scratch.setUint32(4, 0);
    return _scratch.getFloat64(0);
  }

  /// The top thirty-two bits of [x] — read big-endian, `ByteData`'s own
  /// default, exactly as `flutter3d_sim`'s copy of this helper does.
  static int _highWord(double x) {
    _scratch.setFloat64(0, x);
    return _scratch.getUint32(0);
  }

  /// [x] with its top thirty-two bits replaced by [high].
  static double _withHighWord(double x, int high) {
    _scratch.setFloat64(0, x);
    _scratch.setUint32(0, high);
    return _scratch.getFloat64(0);
  }

  static final ByteData _scratch = ByteData(8);

  static const double _expOverflow = 709.782712893383973096;
  static const double _expUnderflow = -745.133219101941108420;
  static const double _log2e = 1.44269504088896338700;
  static const double _ln2Hi = 6.93147180369123816490e-01;
  static const double _ln2Lo = 1.90821492927058770002e-10;
  static const double _expP1 = 1.66666666666666019037e-01;
  static const double _expP2 = -2.77777777770155933842e-03;
  static const double _expP3 = 6.61375632143793436117e-05;
  static const double _expP4 = -1.65339022054652515390e-06;
  static const double _expP5 = 4.13813679705723846039e-08;
  static const double _two54 = 1.80143985094819840000e+16;
  static const double _logLg1 = 6.666666666666735130e-01;
  static const double _logLg2 = 3.999999999940941908e-01;
  static const double _logLg3 = 2.857142874366239149e-01;
  static const double _logLg4 = 2.222219843214978396e-01;
  static const double _logLg5 = 1.818357216161805012e-01;
  static const double _logLg6 = 1.531383769920937332e-01;
  static const double _logLg7 = 1.479819860511658591e-01;
}

/// `x` raised to `y`, for `x > 0` only — see the library doc for the scope
/// this deliberately does not cover.
double powPositive(double x, double y) {
  if (x <= 0.0 || x.isNaN || y.isNaN) return double.nan;
  if (y == 0.0) return 1.0;
  if (x == 1.0) return 1.0;
  return _Portable.exp(y * _Portable.log(x));
}
