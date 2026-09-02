/// The arithmetic four packages had each written out for themselves.
///
///     flutter test test/motion_test.dart
///
/// Each of these is short enough to retype, which is why it was retyped: the
/// shortest way round a circle existed seven times, the clamped step three
/// times, and the easing factor at six call sites. What a test buys here is not
/// confidence in ten lines of arithmetic — it is that the copies which come
/// back can be compared against something.
library;

import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  group('the shortest way round', () {
    test('goes the short way across the wrap point', () {
      // **The bug this exists to prevent, in the one place it happens.** A
      // heading a hair either side of south is two angles a whole turn apart by
      // subtraction, and a body that blends between them spins once, in front
      // of whoever is watching, once a lap.
      final delta = shortestAngle(math.pi - 0.1, -math.pi + 0.1);

      expect(delta, closeTo(0.2, 1e-9));
    });

    test('and answers within half a turn either way', () {
      for (final from in <double>[-7.0, -math.pi, 0.0, 1.0, math.pi, 9.0]) {
        for (final to in <double>[-9.0, -1.0, 0.0, 2.0, math.pi, 8.0]) {
          final delta = shortestAngle(from, to);
          expect(delta, greaterThan(-math.pi - 1e-9));
          expect(delta, lessThanOrEqualTo(math.pi + 1e-9));
          // And it really is the way round to that angle.
          final arrived = shortestAngle(from + delta, to);
          expect(
            arrived.abs(),
            lessThan(1e-9),
            reason: 'from $from to $to landed somewhere else',
          );
        }
      }
    });

    test('and returns from a NaN rather than spinning on it', () {
      // **Not a hypothetical.** Two of the seven copies were `while` loops, and
      // a `while (delta > pi)` given a NaN either exits at once with the NaN or
      // never exits at all, depending on which way the comparison is written.
      // The modulo form always returns, which turns a frozen frame into a
      // visible wrong number.
      expect(shortestAngle(double.nan, 1.0).isNaN, isTrue);
      expect(shortestAngle(0.0, double.nan).isNaN, isTrue);
    });
  });

  group('approaching a target', () {
    test('never overshoots', () {
      expect(approach(0.0, 1.0, 10.0), 1.0);
      expect(approach(1.0, 0.0, 10.0), 0.0);
    });

    test('and moves by the step when the target is further off', () {
      expect(approach(0.0, 10.0, 2.0), closeTo(2.0, 1e-9));
      expect(approach(0.0, -10.0, 2.0), closeTo(-2.0, 1e-9));
    });

    test('and an unlimited step arrives rather than becoming a NaN', () {
      // A mover with no speed limit asks for exactly this, and `0 * infinity`
      // is what the obvious arithmetic gives it.
      expect(approach(3.0, 7.0, double.infinity), 7.0);
    });
  });

  test('turning is the two of them together', () {
    // The composition three of the copies were: a monster facing a player, a
    // runner facing where it is going, a driver correcting a line.
    expect(
      turnedTowards(math.pi - 0.1, -math.pi + 0.1, 1.0),
      closeTo(math.pi + 0.1, 1e-9),
    );
    expect(turnedTowards(0.0, 3.0, 0.5), closeTo(0.5, 1e-9));
  });

  group('the easing factor', () {
    test('is the same motion at any frame rate', () {
      // **The property the whole fixed step exists to protect**, and the reason
      // this is a function rather than a multiply: `rate * dt` is a spring
      // whose stiffness depends on how fast the machine is.
      //
      // A tenth of a second at a stiff rate, which is where the two differ
      // most — over a whole second everything saturates and the question stops
      // being visible.
      double travel(double dt, int steps) {
        var value = 0.0;
        for (var i = 0; i < steps; i++) {
          value += (1.0 - value) * easeFactor(12.0, dt);
        }
        return value;
      }

      final slow = travel(1 / 30.0, 3);
      final fast = travel(1 / 240.0, 24);

      // Both land on `1 - exp(-1.2)`, to the last bit.
      expect(fast, closeTo(slow, 1e-12));
      expect(fast, closeTo(0.6988, 1e-3));
    });

    test('and a plain multiply is not', () {
      // The comparison, so the claim above is measured rather than asserted.
      // The same tenth of a second comes out at 0.784 on a slow machine and
      // 0.708 on a fast one — eight per cent of the whole travel, which is a
      // camera that lags differently on two machines running the same game.
      double travel(double dt, int steps) {
        var value = 0.0;
        for (var i = 0; i < steps; i++) {
          value += (1.0 - value) * (12.0 * dt);
        }
        return value;
      }

      final slow = travel(1 / 30.0, 3);
      final fast = travel(1 / 240.0, 24);

      expect(slow, closeTo(0.784, 1e-3));
      expect(fast, closeTo(0.708, 1e-3));
      expect((slow - fast).abs(), greaterThan(0.05));
    });

    test('and nothing at all happens at a rate of nought', () {
      expect(easeFactor(0.0, 1.0), 0.0);
      expect(easeFactor(-1.0, 1.0), 0.0);
      expect(easeFactor(4.0, 0.0), 0.0);
    });
  });
}
