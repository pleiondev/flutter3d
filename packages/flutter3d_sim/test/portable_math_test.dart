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
      ('exp', 67011626, (int i) => Portable.exp(_a[i] % 4.0)),
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
