/// The functions a step is allowed to call, asked both questions.
///
///     dart test test/portable_math_test.dart                  # this VM
///     dart test --platform chrome test/portable_math_test.dart # a browser
///
/// Two questions, and they are independent:
///
///  1. **Is it the same everywhere?** One digest per function over the same
///     twenty-thousand-argument sweep `parity_test.dart` uses. A single
///     recorded number per row, not a set — `dart:math`'s rows carry a set
///     because two platforms genuinely answer differently and the table's job
///     is to say so. These may not, and a second answer appearing is the
///     failure this whole library exists to make impossible.
///
///  2. **Is it right?** The same sweep against `dart:math`, in units in the
///     last place. Portable and wrong is a physics bug that no parity test
///     would ever report: both platforms would compute the same wrong number
///     and every checkpoint would match.
///
/// The second question is why this file is longer than it looks like it should
/// be. A polynomial that is out by a thousandth still passes every digest.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  group('the same answer everywhere', () {
    // Recorded on macOS-arm64 under the VM, 2026-09-05, and matched by Chrome.
    //
    // **One number apiece, and that is the claim.** `parity_test.dart`'s table
    // of `dart:math` rows carries two digests for every transcendental,
    // because the VM and a browser give different bits. These rows say a
    // second number cannot appear: nothing below asks the machine anything.
    for (final row in <(String, int, double Function(int))>[
      ('sin', 3089570949, (int i) => Portable.sin(_a[i])),
      ('cos', 70541037, (int i) => Portable.cos(_a[i])),
      ('tan', 2305898401, (int i) => Portable.tan(_a[i])),
      ('atan', 546930916, (int i) => Portable.atan(_a[i])),
      ('atan2', 12031001, (int i) => Portable.atan2(_a[i], _b[i])),
      ('asin', 864263681, (int i) => Portable.asin(_a[i].abs() % 1.0)),
      // Folded onto -1 to 1 rather than 0 to 1, because `acos` is the one
      // inverse whose two halves are not each other's mirror image: the answer
      // runs from 0 to π rather than either side of nothing.
      ('acos', 3104191014, (int i) => Portable.acos(_a[i].abs() % 2.0 - 1.0)),
      ('exp', 67011626, (int i) => Portable.exp(_a[i] % 4.0)),
      // The sweep's own magnitudes, which span eleven decades and so reach both
      // the subnormal scaling and the ordinary path.
      ('log', 1558536927, (int i) => Portable.log(_a[i].abs())),
      (
        'pow',
        1395560049,
        (int i) => Portable.pow(_a[i].abs() % 10.0, _b[i] % 4.0),
      ),
    ]) {
      final (name, expected, at) = row;
      test('$name gives one answer, not one per platform', () {
        expect(
          StateDigest.of(<double>[for (var i = 0; i < _sweep; i++) at(i)]),
          expected,
          reason:
              'Portable.$name answered differently here than on the platform '
              'this was recorded on. That is not a tolerance being missed — '
              'everything in that function is IEEE arithmetic over the same '
              'bits, so a difference means a platform whose `+`, `*` or `/` is '
              'not what the specification says, or an edit to the function '
              'that changed its answers. Either is news.',
        );
      });
    }

    test('sinCos agrees with sin and cos taken apart', () {
      // The pair exists to reduce the argument once. If it ever stopped
      // agreeing with the two functions it stands in for, a call site would
      // change meaning by being tidied.
      for (var i = 0; i < 2000; i++) {
        final both = Portable.sinCos(_a[i]);
        expect(both.sin, Portable.sin(_a[i]));
        expect(both.cos, Portable.cos(_a[i]));
      }
    });
  });

  group('and the right answer', () {
    // Two units in the last place, over the whole sweep. Not correctly rounded
    // and not claimed to be: what is being held is that the polynomial is the
    // function, so a coefficient typed wrong fails here rather than becoming a
    // simulation that is portable and mistaken.
    for (final row
        in <(String, double Function(double), double Function(double))>[
          ('sin', Portable.sin, math.sin),
          ('cos', Portable.cos, math.cos),
          ('atan', Portable.atan, math.atan),
        ]) {
      final (name, ours, theirs) = row;
      test('$name is within two ulp of dart:math', () {
        var worst = 0.0;
        var worstAt = 0.0;
        for (var i = 0; i < _sweep; i++) {
          final error = _ulpsApart(ours(_a[i]), theirs(_a[i]));
          if (error > worst) {
            worst = error;
            worstAt = _a[i];
          }
        }
        expect(worst, lessThanOrEqualTo(2.0), reason: '$name at $worstAt');
      });
    }

    test('tan is within four ulp of dart:math away from its poles', () {
      // Wider, and the library doc says why: this one is `sin` over `cos`, so
      // it carries both errors and the division's. Arguments within a
      // hundredth of a pole are skipped rather than given a looser bound —
      // there the answer is enormous and one ulp of `cos` is worth thousands
      // of ulp of the quotient, which is a property of the tangent rather than
      // of this implementation.
      var worst = 0.0;
      for (var i = 0; i < _sweep; i++) {
        final x = _a[i];
        if (math.cos(x).abs() < 0.01) continue;
        final error = _ulpsApart(Portable.tan(x), math.tan(x));
        if (error > worst) worst = error;
      }
      expect(worst, lessThanOrEqualTo(4.0));
    });

    test('atan2 is within two ulp of dart:math', () {
      var worst = 0.0;
      for (var i = 0; i < _sweep; i++) {
        final error = _ulpsApart(
          Portable.atan2(_a[i], _b[i]),
          math.atan2(_a[i], _b[i]),
        );
        if (error > worst) worst = error;
      }
      expect(worst, lessThanOrEqualTo(2.0));
    });

    test('asin is within four ulp of dart:math, including at the ends', () {
      var worst = 0.0;
      for (var i = 0; i < _sweep; i++) {
        final x = _a[i].abs() % 1.0;
        final error = _ulpsApart(Portable.asin(x), math.asin(x));
        if (error > worst) worst = error;
      }
      // The place the identity behind `asin` is supposed to hold up, and the
      // reason `(1 - x)(1 + x)` is written that way rather than as `1 - x²`.
      for (final x in <double>[1.0, -1.0, 0.9999999999, -0.9999999999]) {
        final error = _ulpsApart(Portable.asin(x), math.asin(x));
        if (error > worst) worst = error;
      }
      expect(worst, lessThanOrEqualTo(4.0));
    });

    test('acos is within two ulp of dart:math, including at the ends', () {
      var worst = 0.0;
      var worstAt = 0.0;
      for (var i = 0; i < _sweep; i++) {
        final x = _a[i].abs() % 2.0 - 1.0;
        final error = _ulpsApart(Portable.acos(x), math.acos(x));
        if (error > worst) {
          worst = error;
          worstAt = x;
        }
      }
      // Where the shorter `π/2 - asin(x)` gives up: the answer there is tiny
      // and the subtraction it comes out of is between two numbers near π/2, so
      // most of the digits cancel. This form is the reason the bound is two
      // here and four for `asin`.
      for (final x in <double>[
        1.0,
        -1.0,
        0.9999999999,
        -0.9999999999,
        0.0,
        1e-300,
      ]) {
        final error = _ulpsApart(Portable.acos(x), math.acos(x));
        if (error > worst) {
          worst = error;
          worstAt = x;
        }
      }
      expect(worst, lessThanOrEqualTo(2.0), reason: 'acos at $worstAt');
    });

    test('log is within two ulp of dart:math at every scale', () {
      var worst = 0.0;
      var worstAt = 0.0;
      for (var i = 0; i < _sweep; i++) {
        // The sweep's magnitudes, then the same magnitudes pushed to both ends
        // of the exponent range: the small end is where the argument goes
        // subnormal and the reduction has to scale it up by 2^54 and pay the
        // exponent back, which no ordinary argument exercises.
        for (final x in <double>[
          _a[i].abs(),
          _a[i].abs() * 1e-300,
          _a[i].abs() * 1e300,
        ]) {
          if (x == 0.0 || !x.isFinite) continue;
          final error = _ulpsApart(Portable.log(x), math.log(x));
          if (error > worst) {
            worst = error;
            worstAt = x;
          }
        }
      }
      // The two places the mantissa normalisation changes its mind, either side
      // of one, where an off-by-one in the carry would show and nowhere else.
      for (final x in <double>[
        0.5,
        2.0,
        1.0000000001,
        0.9999999999,
        math.sqrt2,
        math.sqrt2 / 2,
      ]) {
        final error = _ulpsApart(Portable.log(x), math.log(x));
        if (error > worst) {
          worst = error;
          worstAt = x;
        }
      }
      expect(worst, lessThanOrEqualTo(2.0), reason: 'log at $worstAt');
    });

    test('pow is within two ulp of dart:math, and not by way of exp', () {
      // **The measurement this function exists because of.** `exp(y · log x)`
      // out of the two functions above passes every digest and is out by
      // twenty-six units in the last place at `y = 1.5` and seventy-nine at
      // `y = 5`. The exponents below include both, so a future tidy-up back to
      // the two-line version fails here rather than shipping.
      var worst = 0.0;
      var worstAt = '';
      void measure(double x, double y) {
        final error = _ulpsApart(Portable.pow(x, y), math.pow(x, y).toDouble());
        if (error > worst) {
          worst = error;
          worstAt = '$x ^ $y';
        }
      }

      for (var i = 0; i < _sweep; i++) {
        final base = _a[i].abs() % 10.0;
        if (base == 0.0) continue;
        for (final y in <double>[_b[i] % 8.0, _b[i], 1.5, 5.0, -3.25]) {
          measure(base, y);
        }
        // A negative base with a whole exponent, which is the branch where the
        // sign is taken out at the front and multiplied back in at the end.
        measure(-base - 0.001, (_b[i] * 6.0).roundToDouble());
        // A base within a billionth of one against an enormous exponent: the
        // separate short path, where the logarithm is four terms of a series
        // because `f/(2 + f)` would be nothing but rounding error.
        measure(1.0 + _a[i] * 1e-9, _b[i] * 1e9);
      }
      expect(worst, lessThanOrEqualTo(2.0), reason: 'pow at $worstAt');
    });

    test('exp is within two ulp of dart:math across its range', () {
      var worst = 0.0;
      var worstAt = 0.0;
      for (var i = 0; i < _sweep; i++) {
        // The sweep's own values, and then spread over the whole range the
        // function has: a damping term is small and negative, but a library
        // that is only right there is a trap for the next caller.
        for (final x in <double>[_a[i] % 4.0, _a[i] * 100.0, _a[i] * 700.0]) {
          final error = _ulpsApart(Portable.exp(x), math.exp(x));
          if (error > worst) {
            worst = error;
            worstAt = x;
          }
        }
      }
      expect(worst, lessThanOrEqualTo(2.0), reason: 'exp at $worstAt');
    });
  });

  group('the edges', () {
    test('a sine and a cosine of nothing are nought and one', () {
      expect(Portable.sin(0.0), 0.0);
      expect(Portable.cos(0.0), 1.0);
      expect(Portable.exp(0.0), 1.0);
      expect(Portable.atan(0.0), 0.0);
      expect(Portable.asin(0.0), 0.0);
    });

    test('the quarter turns land where they should', () {
      // Where the reduction changes quadrant, which is where a reduction that
      // is off by one is visible and nowhere else.
      for (var turn = -8; turn <= 8; turn++) {
        final x = turn * (math.pi / 2.0);
        expect(Portable.sin(x), closeTo(math.sin(x), 1e-15), reason: 'sin $x');
        expect(Portable.cos(x), closeTo(math.cos(x), 1e-15), reason: 'cos $x');
      }
    });

    test('and so does an angle far from the origin', () {
      // A thousand turns. The two-piece π/2 is what keeps this honest; with a
      // single double for π/2 the remainder here is wrong in its fourth digit.
      for (final x in <double>[1000.0, -1000.0, 6283.185307179586, 12345.678]) {
        expect(Portable.sin(x), closeTo(math.sin(x), 1e-12), reason: 'sin $x');
        expect(Portable.cos(x), closeTo(math.cos(x), 1e-12), reason: 'cos $x');
      }
    });

    test('atan2 answers every quadrant and both signs of zero', () {
      expect(Portable.atan2(0.0, 1.0), 0.0);
      expect(Portable.atan2(-0.0, 1.0), -0.0);
      expect(Portable.atan2(0.0, -1.0), closeTo(math.pi, 1e-15));
      expect(Portable.atan2(-0.0, -1.0), closeTo(-math.pi, 1e-15));
      expect(Portable.atan2(1.0, 0.0), closeTo(math.pi / 2, 1e-15));
      expect(Portable.atan2(-1.0, 0.0), closeTo(-math.pi / 2, 1e-15));
      expect(Portable.atan2(1.0, 1.0), closeTo(math.pi / 4, 1e-15));
      expect(Portable.atan2(-1.0, -1.0), closeTo(-3 * math.pi / 4, 1e-15));
    });

    test('what is not a number stays not a number', () {
      expect(Portable.sin(double.nan).isNaN, isTrue);
      expect(Portable.sin(double.infinity).isNaN, isTrue);
      expect(Portable.cos(double.negativeInfinity).isNaN, isTrue);
      expect(Portable.tan(double.nan).isNaN, isTrue);
      expect(Portable.atan(double.nan).isNaN, isTrue);
      expect(Portable.atan2(double.nan, 1.0).isNaN, isTrue);
      expect(Portable.exp(double.nan).isNaN, isTrue);
      // Outside the domain, which a tyre curve can reach when a slip angle is
      // divided by a load that went to nothing.
      expect(Portable.asin(1.5).isNaN, isTrue);
      expect(Portable.asin(-1.5).isNaN, isTrue);
    });

    test('an exponent past the ends saturates rather than wandering', () {
      expect(Portable.exp(1000.0), double.infinity);
      expect(Portable.exp(-1000.0), 0.0);
      expect(Portable.exp(709.0).isFinite, isTrue);
      expect(Portable.exp(-745.0) > 0.0, isTrue);
    });

    test('atan reaches its asymptote', () {
      expect(Portable.atan(double.infinity), closeTo(math.pi / 2, 1e-15));
      expect(
        Portable.atan(double.negativeInfinity),
        closeTo(-math.pi / 2, 1e-15),
      );
      expect(Portable.asin(1.0), closeTo(math.pi / 2, 1e-15));
      expect(Portable.asin(-1.0), closeTo(-math.pi / 2, 1e-15));
    });

    test('an arc cosine runs from π down to nothing', () {
      // Exactly nought at the top end rather than nearly: `atan2(0, 1)` is the
      // zero it is given, and a formula built on a subtraction would land a
      // couple of ulp away instead.
      expect(Portable.acos(1.0), 0.0);
      expect(Portable.acos(-1.0), closeTo(math.pi, 1e-15));
      expect(Portable.acos(0.0), closeTo(math.pi / 2, 1e-15));
      expect(Portable.acos(1.5).isNaN, isTrue);
      expect(Portable.acos(-1.5).isNaN, isTrue);
      expect(Portable.acos(double.nan).isNaN, isTrue);
    });

    test('a logarithm answers at both ends of what a double can hold', () {
      expect(Portable.log(1.0), 0.0);
      expect(Portable.log(0.0), double.negativeInfinity);
      expect(Portable.log(-0.0), double.negativeInfinity);
      expect(Portable.log(-1.0).isNaN, isTrue);
      expect(Portable.log(double.nan).isNaN, isTrue);
      expect(Portable.log(double.infinity), double.infinity);
      // The smallest subnormal there is. Finite, and the scaling by 2^54 is the
      // only reason it is: read straight, its exponent field says nothing.
      expect(Portable.log(double.minPositive).isFinite, isTrue);
      expect(
        Portable.log(double.minPositive),
        closeTo(math.log(double.minPositive), 1e-12),
      );
    });

    test('a power answers its conventions rather than its limits', () {
      // The conventions, in the order the function takes them.
      expect(Portable.pow(0.0, 0.0), 1.0);
      expect(Portable.pow(7.5, 0.0), 1.0);
      expect(Portable.pow(double.nan, 0.0), 1.0);
      expect(Portable.pow(1.0, 42.5), 1.0);
      expect(Portable.pow(1.0, double.nan), 1.0);
      expect(Portable.pow(-1.0, double.infinity), 1.0);

      // A negative base, where the parity of a whole exponent is the sign and
      // anything else is outside the domain.
      expect(Portable.pow(-2.0, 3.0), -8.0);
      expect(Portable.pow(-2.0, 2.0), 4.0);
      expect(Portable.pow(-2.0, 2.5).isNaN, isTrue);
      expect(Portable.pow(-0.0, 3.0), -0.0);
      expect(Portable.pow(-0.0, 0.5), 0.0);

      // Past both ends. 2^1024 is the first exponent that is not a double and
      // 2^-1075 the first that is not a subnormal, so the pair either side of
      // each is where a bound written one out would show.
      expect(Portable.pow(2.0, 1024.0), double.infinity);
      expect(Portable.pow(2.0, 1023.0), math.pow(2.0, 1023.0));
      expect(Portable.pow(2.0, -1075.0), 0.0);
      expect(Portable.pow(2.0, -1074.0), double.minPositive);
      // Between those two the answer is subnormal and there is no exponent
      // field left to write the scaling into, so it has to be multiplied in
      // instead — a separate line, and this is what stands over it.
      expect(Portable.pow(2.0, -1023.0), math.pow(2.0, -1023.0));
      expect(Portable.pow(2.0, -1022.0), math.pow(2.0, -1022.0));
      expect(Portable.pow(0.0, -1.0), double.infinity);
    });
  });
}

/// How far apart [a] and [b] are, in units of the last place at [b].
///
/// The unit an approximation is judged in: a relative error means nothing where
/// a result is nearly zero and an absolute one means nothing where it is large,
/// while "how many representable doubles apart" is the same question at every
/// scale.
///
/// **Measured as a distance over an ulp rather than by subtracting bit
/// patterns**, which is the version this file had first and which was wrong in
/// a way worth keeping: the bit patterns are near 2^62, and their difference
/// taken in a `double` rounds to the nearest multiple of 1024. Every row
/// reported a failure of exactly 512 or 1024 — powers of two, which is what an
/// instrument looks like when it is measuring itself.
double _ulpsApart(double a, double b) {
  if (a == b) return 0.0;
  if (a.isNaN && b.isNaN) return 0.0;
  if (a.isNaN || b.isNaN || a.isInfinite || b.isInfinite) {
    return double.infinity;
  }
  return (a - b).abs() / _ulpSize(b);
}

/// The gap between [x] and the next double away from zero.
///
/// Found by adding one to the mantissa and subtracting, which is exact. Read
/// through `ByteData` in halves because a browser's integers stop being exact
/// at 2^53 and a double is sixty-four bits wide.
double _ulpSize(double x) {
  final magnitude = x.abs();
  if (magnitude == 0.0 || !magnitude.isFinite) return double.minPositive;
  _bits.setFloat64(0, magnitude);
  final low = _bits.getUint32(4);
  if (low == 0xFFFFFFFF) {
    _bits.setUint32(0, _bits.getUint32(0) + 1);
    _bits.setUint32(4, 0);
  } else {
    _bits.setUint32(4, low + 1);
  }
  return _bits.getFloat64(0) - magnitude;
}

final ByteData _bits = ByteData(8);

/// The same sweep `parity_test.dart` uses, for the same reason: [GameRandom] is
/// the one generator this repository has proved gives the same sequence
/// everywhere, so both platforms ask about identical arguments.
const int _sweep = 20000;

List<double> _sweepArguments(int seed) {
  final dice = GameRandom(seed);
  return <double>[
    for (var i = 0; i < _sweep; i++)
      switch (i % 4) {
        0 => dice.nextDouble() * 2.0 - 1.0,
        1 => (dice.nextDouble() * 2.0 - 1.0) * math.pi * 2.0,
        2 => (dice.nextDouble() * 2.0 - 1.0) * 1000.0,
        _ => (dice.nextDouble() * 2.0 - 1.0) * 1e-4,
      },
  ];
}

final List<double> _a = _sweepArguments(1);
final List<double> _b = _sweepArguments(2);
