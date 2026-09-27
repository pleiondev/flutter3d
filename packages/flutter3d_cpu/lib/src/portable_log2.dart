/// A base-two logarithm that answers the same bits on every platform.
///
/// **Why this file exists.** `math.log` is the platform's libm, and the
/// specification pins neither its accuracy nor its rounding: the same argument
/// gives different last bits under the VM on macOS and under the VM on Linux.
/// For most arithmetic that is a rounding difference nobody can see. For a mip
/// level it is not, because the number is immediately floored — a footprint
/// that lands a fraction either side of a whole level picks a different
/// texture, and the pixels that read from it move by a hundred out of
/// twenty-five five. `anisotropic-floor` is the scene built to sit exactly
/// there: 2059 of its 172800 pixels differed between a reference recorded on
/// macOS and the same code run on a Linux runner, and nothing else in
/// seventy-eight scenes differed at all.
///
/// **The same rule the simulation already keeps.** `flutter3d_sim`'s
/// `Portable` exists for this, and a step in that package is forbidden from
/// calling `dart:math` at all. This is the graphics half of the same problem,
/// and the reason it is a second implementation rather than a dependency is
/// the layering: a backend that reached into the simulation to sample a
/// texture would be an arrow pointing the wrong way through the whole
/// repository. What is copied is the idea, not the code — `Portable.log` is a
/// full natural logarithm over fdlibm's own argument reduction, and this is a
/// base-two logarithm over sixteen lines.
///
/// **What makes it portable.** Every operation below is one the IEEE 754
/// specification pins to a single answer: reading the bits of a double,
/// addition, subtraction, multiplication and division. There is no table, no
/// library call and nothing that a C runtime gets to have an opinion about.
library;

import 'dart:typed_data';

/// Scratch for reading a double's bits. One buffer rather than one per call:
/// this runs per texel of every mipped sample in a frame.
final ByteData _bits = ByteData(8);

/// `log2(x)` for a finite `x > 0`, to within an ulp or two of the exact
/// value, identically on every platform.
///
/// The exponent comes out of the bit pattern, which is exact — a double *is*
/// `mantissa * 2^exponent`, so the whole part of the answer is already
/// written down. What is left is the logarithm of a mantissa in `[1, 2)`,
/// and that is where the series below does its work.
double portableLog2(double x) {
  if (!(x > 0.0) || x.isInfinite || x.isNaN) {
    // The callers never ask: a footprint is positive and finite before it
    // reaches here. Answering rather than throwing keeps a texel from taking
    // a frame down if one ever does.
    return x.isNaN ? x : (x <= 0.0 ? double.negativeInfinity : x);
  }

  _bits.setFloat64(0, x);
  final high = _bits.getUint32(0);
  var exponent = ((high >> 20) & 0x7FF) - 1023;

  // Subnormal: no implicit leading one, so the exponent read above is wrong.
  // Scale into the normal range by a power of two, which is exact, and take
  // the scaling back off the answer.
  if (exponent == -1023) {
    _bits.setFloat64(0, x * 18446744073709551616.0); // 2^64
    exponent = ((_bits.getUint32(0) >> 20) & 0x7FF) - 1023 - 64;
  }

  // The mantissa alone, as a double in [1, 2): keep the low bits, force the
  // exponent field to that of 1.0.
  _bits.setUint32(0, (_bits.getUint32(0) & 0x000FFFFF) | 0x3FF00000);
  var mantissa = _bits.getFloat64(0);

  // Centre the mantissa on 1 rather than letting it run to 2. Halving is
  // exact and costs one more on the exponent, and it shrinks the largest
  // `t` below from 1/3 to about 0.172 — which is what lets six terms reach
  // the last bit instead of twenty.
  if (mantissa > 1.4142135623730951) {
    mantissa *= 0.5;
    exponent += 1;
  }

  // The classic atanh series: with `t = (m - 1) / (m + 1)`,
  // `ln(m) = 2 * (t + t^3/3 + t^5/5 + ...)`. It converges on |t| rather than
  // on |m - 1|, which is the whole reason for the halving above.
  //
  // Eleven terms, and the count was measured rather than guessed. |t| never
  // exceeds 0.1716 after the halving, so the first term left out is
  // `2 * t^23 / 23`, about 1e-18 — under the last bit of a double for every
  // mantissa this can be handed. Stopping at six terms, which looks like
  // plenty, leaves 3e-11, and that is the difference between agreeing with
  // libm to the bit and disagreeing with it in the twelfth place.
  final t = (mantissa - 1.0) / (mantissa + 1.0);
  final t2 = t * t;
  final series =
      t *
      (2.0 +
          t2 *
              (0.6666666666666666 +
                  t2 *
                      (0.4 +
                          t2 *
                              (0.2857142857142857 +
                                  t2 *
                                      (0.2222222222222222 +
                                          t2 *
                                              (0.1818181818181818 +
                                                  t2 *
                                                      (0.15384615384615385 +
                                                          t2 *
                                                              (0.13333333333333333 +
                                                                  t2 *
                                                                      (0.11764705882352941 +
                                                                          t2 *
                                                                              (0.10526315789473684 + t2 * 0.09523809523809523))))))))));

  // 1 / ln(2), to the last bit a double holds.
  return exponent + series * 1.4426950408889634;
}
