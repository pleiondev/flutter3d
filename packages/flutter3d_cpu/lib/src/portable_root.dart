/// Roots, and the fractional powers built from them, that answer the same bits
/// on every platform.
///
/// **Why this file exists.** The sRGB curve is `x^2.4` one way and `x^(1/2.4)`
/// the other, and the software rasteriser runs one of them on every pixel of
/// every frame. `math.pow` is the platform's libm, which the specification
/// does not pin to the last bit, so the same frame came out one step apart in
/// the last place on macOS and on a Linux runner — across 56-74% of a lit
/// scene, which is what switched the render lane off on 2026-09-22.
/// `portable_log2.dart` is the same problem at the mip level, solved the same
/// way.
///
/// **What makes it portable.** Reading a double's bits, addition,
/// subtraction, multiplication and division: the operations IEEE 754 rounds to
/// one answer. Newton's method uses nothing else, and it starts from a power
/// of two built from the bits, so the sequence of values it passes through is
/// the same everywhere and so is where it stops.
///
/// Both exponents are rationals with small denominators, which is what makes
/// this possible at all: `2.4 = 12/5` and `1/2.4 = 5/12`, so each is an
/// integer power of a fifth or a twelfth root. A twelfth root is two square
/// roots of a cube root, and `sqrt` is correctly rounded by the same standard.
library;

import 'dart:math' as math;
import 'dart:typed_data';

final ByteData _bits = ByteData(8);

/// Answers [portableRoot] has already given, by argument: a direct-mapped
/// table, one entry per slot, indexed by the argument's own bits.
///
/// **The same bits either way.** The root is a pure function of `x` and `n`,
/// so an answer read back from here is the one the loop below would have
/// stopped at. What makes it worth keeping is where the calls come from: the
/// sRGB curve on every fragment of a surface, with a material's tint and the
/// texel of a one-pixel fallback map among its arguments — the same few
/// values, frame after frame, each costing a Newton descent.
const int _memoSlots = 4096;
final Float64List _memoX = Float64List(_memoSlots)
  ..fillRange(0, _memoSlots, double.nan);
final Int32List _memoN = Int32List(_memoSlots);
final Float64List _memoRoot = Float64List(_memoSlots);

/// The [n]th root of [x], for `x > 0` and a small `n > 1`, identically on
/// every platform and to within an ulp or two of the exact value.
///
/// Newton's method on `y^n − x` descends monotonically onto the root from any
/// start above it, because the function is convex there. The start is the
/// power of two just over the root, read off the exponent — so the loop needs
/// no guess and no iteration count, only the rule that it stops the first time
/// a step fails to go down.
double portableRoot(double x, int n) {
  if (!(x > 0.0)) return 0.0;
  if (x.isInfinite) return x;

  // Little-endian, so the high word — sign, exponent and the top of the
  // mantissa — is the second one; the byte order changes where the word is
  // read from and nothing about its value.
  _bits.setFloat64(0, x, Endian.little);
  final high = _bits.getUint32(4, Endian.little);
  final low = _bits.getUint32(0, Endian.little);
  final slot = (low ^ (low >> 13) ^ high ^ (high >> 11) ^ n) & (_memoSlots - 1);
  if (_memoX[slot] == x && _memoN[slot] == n) return _memoRoot[slot];

  final exponent = ((high >> 20) & 0x7FF) - 1023;
  // x < 2^(exponent + 1), so its root is under 2^((exponent + 1) / n), and
  // rounding that exponent up keeps the start above the root. Built by
  // doubling or halving, each of which is exact.
  final k = ((exponent + 1) / n).ceil();
  var y = 1.0;
  for (var i = 0; i < k.abs(); i++) {
    y = k > 0 ? y * 2.0 : y * 0.5;
  }

  final m = n - 1;
  while (true) {
    var power = y;
    for (var i = 1; i < m; i++) {
      power *= y;
    }
    final next = (m * y + x / power) / n;
    if (!(next < y)) break;
    y = next;
  }
  _memoX[slot] = x;
  _memoN[slot] = n;
  _memoRoot[slot] = y;
  return y;
}

/// `x^(12/5)` for `x >= 0`: the sRGB decoding curve's exponent.
double portablePow12Over5(double x) {
  if (!(x > 0.0)) return 0.0;
  final fifth = portableRoot(x, 5);
  final x2 = x * x;
  return x2 * fifth * fifth;
}

/// `x^(5/12)` for `x >= 0`: the sRGB encoding curve's exponent.
double portablePow5Over12(double x) {
  if (!(x > 0.0)) return 0.0;
  final twelfth = math.sqrt(math.sqrt(portableRoot(x, 3)));
  final t2 = twelfth * twelfth;
  return t2 * t2 * twelfth;
}

/// `x^(11/5)` for `x >= 0`: the `pow(2.2)` that closes AgX's outset.
double portablePow11Over5(double x) {
  if (!(x > 0.0)) return 0.0;
  return x * x * portableRoot(x, 5);
}
