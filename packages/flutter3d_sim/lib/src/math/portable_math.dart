/// The functions a step is allowed to call, computed the same way everywhere.
///
/// ## Why this exists
///
/// `parity_test.dart` in this package asked twelve `dart:math` functions for
/// twenty thousand answers apiece, under the VM and under Chrome, and digested
/// each column. **One matched.** `sqrt` is the one the specification pins;
/// every transcendental — `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`,
/// `exp`, `log` — gave different bits in the two places, and so did every
/// combination of them. There is nothing portable in `dart:math` to build a
/// substitute out of, because on the VM those are the host's libm and in a
/// browser they are whatever that engine ships, and neither IEEE 754 nor the
/// Dart specification says the two agree on the last bit.
///
/// `pow` was the tenth, and it was the interesting one: on macOS-arm64 it
/// matched in both places, which read as a second function the specification
/// had pinned. It had not. A third machine, an x86-64 Ubuntu, answered `pow`
/// differently from either — so what the first measurement saw was two runtimes
/// that happened to share one host's libm, and the conclusion drawn from it was
/// the conclusion a sample of two invites. That is why [pow] is here and why
/// `sqrt` is the only thing this file still asks for.
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
/// Ten: [sin], [cos], [tan], [asin], [acos], [atan], [atan2], [exp], [log] and
/// [pow], plus [sinCos] for the pair a call site usually wants together. That
/// is every name the rule in `tool/structure.dart` refuses, which is the line
/// this list is drawn on — a function the rule forbids and this library does
/// not have is a step with nowhere to go.
///
/// They arrive in a handful of shapes: an angle turned into a direction
/// ([sinCos]), a direction turned back into an angle ([atan2]), the exponential
/// of a damping term ([exp]), the tangent in the bicycle-model steering
/// ([tan]), the arc sine in the tyre curve ([asin]), and a falloff raised to an
/// exponent ([pow]).
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

  /// Arc cosine of [x], in radians, between 0 and π. NaN outside -1 to 1.
  ///
  /// The mirror of [asin] and built the same way, with the two arguments of
  /// [atan2] swapped: the sine of the answer is the square root and its cosine
  /// is `x`, so `atan2(sqrt((1 - x)(1 + x)), x)` is the angle. The factoring of
  /// `1 - x²` earns its keep at the same place and for the same reason.
  ///
  /// **Not `π/2 - asin(x)`**, which is shorter and is a trap: near `x = 1` the
  /// arc cosine is nearly zero while `asin` is nearly π/2, so the subtraction
  /// cancels away most of the digits the answer was supposed to have. The form
  /// here is measured against `dart:math` at two units in the last place across
  /// the whole domain; the subtraction is not.
  static double acos(double x) {
    if (x.isNaN || x < -1.0 || x > 1.0) return double.nan;
    return atan2(math.sqrt((1.0 - x) * (1.0 + x)), x);
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

  /// The natural logarithm of [x]. Negative infinity at zero, NaN below it.
  ///
  /// **The first function here that reads the bits of its argument**, and it has
  /// to: the reduction is `x = 2^k · m` with `m` between √2/2 and √2, and `k` is
  /// the exponent field. Taking it by repeated halving would be a loop whose
  /// length depends on the argument, and taking it through a logarithm would be
  /// circular. [_highWord] is how the exponent is read, and `ByteData` is what
  /// makes that portable — the same eight bytes in the same order everywhere,
  /// which is already the property [_twoTo] and `StateDigest` rest on.
  ///
  /// The mantissa is normalised into the interval by the `+ 0x95F64` trick:
  /// adding that to the mantissa field carries into bit twenty exactly when the
  /// mantissa is above √2, and the carry is both the test and the correction to
  /// `k`. A subnormal argument is scaled up by 2^54 first and pays for it with
  /// `k -= 54`, because its exponent field reads zero and says nothing.
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
      // |f| < 2^-20, where `f/(2+f)` would be all rounding error and the plain
      // series is both shorter and better.
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

    // fdlibm writes this bound as the sign of two subtractions ored together;
    // it is the mantissa field sitting between √2/2 and √2 rounded to twenty
    // bits, and saying so directly costs nothing and cannot be read wrong.
    if (hx >= 0x6147A && hx <= 0x6B851) {
      final hfsq = 0.5 * f * f;
      if (k == 0) return f - (hfsq - s * (hfsq + r));
      return dk * _ln2Hi - ((hfsq - (s * (hfsq + r) + dk * _ln2Lo)) - f);
    }
    if (k == 0) return f - s * (f - r);
    return dk * _ln2Hi - ((s * (f - r) - dk * _ln2Lo) - f);
  }

  /// [x] raised to [y].
  ///
  /// **The long way round, and the short way was measured first.** `exp(y ·
  /// log x)` out of the two functions above is four lines and is wrong: the
  /// logarithm's last two bits are multiplied by `y` before the exponential
  /// magnifies them again, which came out at twenty-six units in the last place
  /// at `y = 1.5` and seventy-nine at `y = 5`, against a bound of two. What
  /// fixes it is what fdlibm does — carry the logarithm in two pieces, base
  /// two, so the product with `y` is formed in something wider than a double
  /// before the exponential sees it. That is the whole reason this function is
  /// two hundred lines instead of four.
  ///
  /// The half of it that is not arithmetic is the special values, and there are
  /// a lot of them because the answer to `pow` at an edge is a convention rather
  /// than a limit: `0^0` is one, `1^NaN` is one, `(-1)^∞` is one, `(-1)^0.5` is
  /// not a number, and a negative base is only allowed a whole-number exponent —
  /// where the parity of that number decides the sign. Every one of those is a
  /// branch below, in the order fdlibm takes them, because the order is
  /// load-bearing: `y == 0` answers before NaN is considered, and NaN answers
  /// before anything reads a bit.
  static double pow(double x, double y) {
    // Both before the NaN test, and deliberately. Anything to the nought is
    // one, and one to anything is one, including when the anything is a NaN —
    // which is what IEEE 754 and C99 say and what `dart:math` answers on the
    // VM. It is *not* what fdlibm's kernel answers, nor what a browser's
    // `Math.pow` does: both call `1^NaN` and `(-1)^∞` not a number. That is a
    // place the two platforms part company like any other, so this file has to
    // choose, and it chooses the standard's answer over the older one.
    if (y == 0.0) return 1.0;
    if (x == 1.0) return 1.0;
    if (x.isNaN || y.isNaN) return double.nan;

    // Whether `y` is a whole number and, if it is, whether it is odd — which is
    // the only thing that lets a negative base through at all. Past 2^53 the
    // gap between doubles is two, so every one of them is even.
    final ay = y.abs();
    final int yIsInt;
    if (y.isInfinite || y != y.truncateToDouble()) {
      yIsInt = 0;
    } else if (ay >= _two53) {
      yIsInt = 2;
    } else {
      yIsInt = ay % 2.0 == 1.0 ? 1 : 2;
    }

    final ax = x.abs();

    if (y.isInfinite) {
      // (-1)^±∞ is one, for the reason above: `x` is exactly one in magnitude
      // and no amount of exponent moves it.
      if (ax == 1.0) return 1.0;
      if (ax > 1.0) return y.isNegative ? 0.0 : double.infinity;
      return y.isNegative ? double.infinity : 0.0;
    }
    if (y == 1.0) return x;
    if (y == -1.0) return 1.0 / x;
    if (y == 2.0) return x * x;
    // A correctly rounded square root beats anything the general path would
    // give. `isNegative` rather than `x >= 0`, so that a negative zero falls
    // through to the special-base branch and answers +0 instead of -0.
    if (y == 0.5 && !x.isNegative) return math.sqrt(x);

    if (ax == 0.0 || ax == 1.0 || ax.isInfinite) {
      // ±0, ±1 and ±∞ are exact at every exponent, and the general path would
      // reach them through a logarithm of zero or infinity.
      var z = ax;
      if (y.isNegative) z = 1.0 / z;
      if (x.isNegative) {
        if (ax == 1.0 && yIsInt == 0) return double.nan;
        if (yIsInt == 1) z = -z;
      }
      return z;
    }

    if (x.isNegative && yIsInt == 0) return double.nan;
    // The sign is settled here and multiplied back in at the very end, so
    // everything between works on a positive base.
    final s = x.isNegative && yIsInt == 1 ? -1.0 : 1.0;

    final ix = _highWord(ax);

    // t1 + t2 is log2(|x|) in two pieces, t1 carrying the top twenty-odd bits
    // with a clear tail so that y·t1 is formed without rounding.
    final double t1;
    final double t2;

    if (ay > 2147483648.0) {
      // |y| past 2^31. The result overflows or underflows for any base that is
      // not within 2^-20 of one, so the only case left needing real work is a
      // base that close — where four terms of the series are the logarithm.
      if (ay > 18446744073709551616.0) {
        if (ix <= 0x3FEFFFFF) return y.isNegative ? double.infinity : 0.0;
        if (ix >= 0x3FF00000) return y.isNegative ? 0.0 : double.infinity;
      }
      if (ix < 0x3FEFFFFF) {
        return y.isNegative ? s * double.infinity : s * 0.0;
      }
      if (ix > 0x3FF00000) {
        return y.isNegative ? s * 0.0 : s * double.infinity;
      }
      final t = ax - 1.0;
      final w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25));
      final u = _ivln2Hi * t;
      final v = t * _ivln2Lo - w * _ivln2;
      t1 = _withLowWordZero(u + v);
      t2 = v - (t1 - u);
    } else {
      var scaled = ax;
      var hi = ix;
      var n = 0;
      if (hi < 0x00100000) {
        scaled *= _two53;
        n -= 53;
        hi = _highWord(scaled);
      }
      n += (hi >> 20) - 0x3FF;
      final mantissa = hi & 0x000FFFFF;
      hi = mantissa | 0x3FF00000;

      // Which of the two anchors the mantissa is measured from — one, or one
      // and a half. Above √3/2 of the upper anchor the exponent is bumped
      // instead, so the ratio below is never far from zero.
      final int piece;
      if (mantissa <= 0x3988E) {
        piece = 0;
      } else if (mantissa < 0xBB67A) {
        piece = 1;
      } else {
        piece = 0;
        n += 1;
        hi -= 0x00100000;
      }
      scaled = _withHighWord(scaled, hi);

      final u = scaled - _powBp[piece];
      final v = 1.0 / (scaled + _powBp[piece]);
      final ss = u * v;
      final sHi = _withLowWordZero(ss);
      // The high half of `scaled + bp[piece]`, assembled from the exponent
      // rather than added, so that the remainder below is exact.
      var tHi = _withHighWord(
        0.0,
        ((hi >> 1) | 0x20000000) + 0x00080000 + (piece << 18),
      );
      final tLo = scaled - (tHi - _powBp[piece]);
      final sLo = v * ((u - sHi * tHi) - sHi * tLo);

      var sq = ss * ss;
      var r =
          sq *
          sq *
          (_powL1 +
              sq *
                  (_powL2 +
                      sq *
                          (_powL3 +
                              sq * (_powL4 + sq * (_powL5 + sq * _powL6)))));
      r += sLo * (sHi + ss);
      sq = sHi * sHi;
      tHi = _withLowWordZero(3.0 + sq + r);
      final tLo2 = r - ((tHi - 3.0) - sq);

      final u2 = sHi * tHi;
      final v2 = sLo * tHi + tLo2 * ss;
      final pHi = _withLowWordZero(u2 + v2);
      final pLo = v2 - (pHi - u2);
      final zHi = _powCpHi * pHi;
      final zLo = _powCpLo * pHi + pLo * _powCp + _powDpLo[piece];

      final e = n.toDouble();
      t1 = _withLowWordZero(((zHi + zLo) + _powDpHi[piece]) + e);
      t2 = zLo - (((t1 - e) - _powDpHi[piece]) - zHi);
    }

    // y·log2(|x|), again in two pieces: y is split so that yHi·t1 is exact.
    final yHi = _withLowWordZero(y);
    final pLo = (y - yHi) * t1 + y * t2;
    var pHi = yHi * t1;
    var z = pLo + pHi;
    final zHiWord = _highWord(z);
    final zLoWord = _lowWord(z);
    if (!z.isNegative && zHiWord >= 0x40900000) {
      // 2^1024 and above is not a double. The equality case is measured rather
      // than assumed: exactly 1024 still rounds down to a finite number unless
      // the discarded tail pushes it over.
      if (zHiWord != 0x40900000 || zLoWord != 0) return s * double.infinity;
      if (pLo + _powOvt > z - pHi) return s * double.infinity;
    } else if ((zHiWord & 0x7FFFFFFF) >= 0x4090CC00) {
      // Below -1075 not even a subnormal survives.
      if (zHiWord != 0xC090CC00 || zLoWord != 0) return s * 0.0;
      if (pLo <= z - pHi) return s * 0.0;
    }

    // 2^(pHi + pLo): the whole part comes out as an exponent and the fraction,
    // now under half, goes through the same polynomial `exp` uses.
    final magnitude = zHiWord & 0x7FFFFFFF;
    var k = (magnitude >> 20) - 0x3FF;
    var whole = 0;
    if (magnitude > 0x3FE00000) {
      final rounded = zHiWord + (0x00100000 >> (k + 1));
      k = ((rounded & 0x7FFFFFFF) >> 20) - 0x3FF;
      // The whole part of z, kept as a double with its fraction masked off.
      // Written as a subtraction rather than as a complemented mask, because a
      // complement is thirty-two bits wide in one of the two places this runs
      // and sixty-four in the other.
      final low = 0x000FFFFF >> k;
      final t = _withHighWord(0.0, rounded - (rounded & low));
      whole = ((rounded & 0x000FFFFF) | 0x00100000) >> (20 - k);
      if (z.isNegative) whole = -whole;
      pHi -= t;
    }

    var t = _withLowWordZero(pLo + pHi);
    final u = t * _lg2Hi;
    final v = (pLo - (t - pHi)) * _lg2 + t * _lg2Lo;
    z = u + v;
    final w = v - (z - u);
    t = z * z;
    final poly =
        z -
        t * (_expP1 + t * (_expP2 + t * (_expP3 + t * (_expP4 + t * _expP5))));
    final r = (z * poly) / (poly - 2.0) - (w + z * w);
    z = 1.0 - (r - z);

    // Adding the whole part to the exponent field is a multiply by a power of
    // two that cannot round. It only fails when the answer is subnormal and
    // there is no exponent field left to write into — the exponent would go
    // negative and land somewhere it does not mean — which is what the other
    // branch is for.
    final assembled = _highWord(z) + whole * 0x00100000;
    if (assembled < 0x00100000) return s * _scaleByPowerOfTwo(z, whole);
    return s * _withHighWord(z, assembled);
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

  /// The top thirty-two bits of [x] — sign, exponent and the high mantissa.
  ///
  /// **Unsigned, and every caller reads it that way.** fdlibm keeps this word in
  /// a signed `int` and tests `hx < 0` to mean a negative argument, which is a
  /// thirty-two-bit habit: one of the two platforms here has sixty-four-bit
  /// integers and the other has doubles pretending to be integers, and neither
  /// agrees with C about what the top bit means. Where fdlibm asks the sign of
  /// the word, the ports above ask `x.isNegative` instead, which is the same
  /// question asked of the number.
  static int _highWord(double x) {
    _scratch.setFloat64(0, x);
    return _scratch.getUint32(0);
  }

  /// The bottom thirty-two bits of [x].
  static int _lowWord(double x) {
    _scratch.setFloat64(0, x);
    return _scratch.getUint32(4);
  }

  /// [x] with its top thirty-two bits replaced by [high].
  static double _withHighWord(double x, int high) {
    _scratch.setFloat64(0, x);
    _scratch.setUint32(0, high);
    return _scratch.getFloat64(0);
  }

  /// [x] with its bottom twenty-eight-odd bits of mantissa thrown away.
  ///
  /// The workhorse of the two-piece arithmetic in [pow]: a number whose low word
  /// is zero has at most twenty-one significant bits left, so the product of two
  /// of them fits in a double exactly and the tail can be recovered by
  /// subtraction. Truncation rather than rounding, because what matters is that
  /// the remainder is exactly representable and not that the head is nearest.
  static double _withLowWordZero(double x) {
    _scratch.setFloat64(0, x);
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

  /// 2^54, the scale that lifts a subnormal into the normal range for [log].
  static const double _two54 = 1.80143985094819840000e+16;

  /// 2^53, where consecutive doubles are two apart and every one of them is
  /// even — which is how [pow] knows the parity of a huge exponent.
  static const double _two53 = 9007199254740992.0;

  /// The logarithm's series in `s = f/(2 + f)`, fitted to the reduced interval.
  static const double _logLg1 = 6.666666666666735130e-01;
  static const double _logLg2 = 3.999999999940941908e-01;
  static const double _logLg3 = 2.857142874366239149e-01;
  static const double _logLg4 = 2.222219843214978396e-01;
  static const double _logLg5 = 1.818357216161805012e-01;
  static const double _logLg6 = 1.531383769920937332e-01;
  static const double _logLg7 = 1.479819860511658591e-01;

  /// The two anchors [pow] measures a mantissa from, and log2 of each in two
  /// pieces. `bp[0]` is one, so its logarithm is nothing and both halves are
  /// zero; `bp[1]` is one and a half, and its logarithm is where the split
  /// starts paying.
  static const List<double> _powBp = <double>[1.0, 1.5];
  static const List<double> _powDpHi = <double>[
    0.0,
    5.84962487220764160156e-01,
  ];
  static const List<double> _powDpLo = <double>[
    0.0,
    1.35003920212974897128e-08,
  ];

  /// (3/2)·(log(x)/log(2) - 1), which is the shape the two anchors leave.
  static const double _powL1 = 5.99999999999994648725e-01;
  static const double _powL2 = 4.28571428578550184252e-01;
  static const double _powL3 = 3.33333329818377432918e-01;
  static const double _powL4 = 2.72728123808534006489e-01;
  static const double _powL5 = 2.30660745775561754067e-01;
  static const double _powL6 = 2.06975017800338417784e-01;

  /// 2/(3·ln2), whole and split, so that the change of base is exact in its
  /// high half and the remainder is carried rather than lost.
  static const double _powCp = 9.61796693925975554329e-01;
  static const double _powCpHi = 9.61796700954437255859e-01;
  static const double _powCpLo = -7.02846165095275826516e-09;

  /// ln2, whole and split, for the trip back from base two.
  static const double _lg2 = 6.93147180559945286227e-01;
  static const double _lg2Hi = 6.93147182464599609375e-01;
  static const double _lg2Lo = -1.90465429995776804525e-09;

  /// 1/ln2, whole and split, for the trip out to base two.
  static const double _ivln2 = 1.44269504088896338700e+00;
  static const double _ivln2Hi = 1.44269502162933349609e+00;
  static const double _ivln2Lo = 1.92596299112661746887e-08;

  /// How far above 1024 the exponent has to reach before the answer is not a
  /// double: -(1024 - log2(largest double + half an ulp)).
  static const double _powOvt = 8.0085662595372944372e-17;
}
