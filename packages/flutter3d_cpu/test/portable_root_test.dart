// The sRGB curve without `math.pow`, and why nothing here compares against it.
//
// `math.pow` is what `portable_root.dart` replaces, and its last bit is the
// platform's: a test holding this to libm would pass on the machine the
// expectations were written on and mean nothing on a Linux runner. What is
// asserted instead is what arithmetic pins — exact roots of exact powers, the
// inverse relation, monotonicity, a round trip through the curve for every
// byte — and a handful of values written out to the last bit, which a change
// to the method has to move on purpose.

import 'package:flutter3d_cpu/src/cpu_shaders_color.dart';
import 'package:flutter3d_cpu/src/portable_root.dart';
import 'package:test/test.dart';

void main() {
  test('an exact power has an exact root', () {
    expect(portableRoot(32.0, 5), 2.0);
    expect(portableRoot(1.0 / 32.0, 5), 0.5);
    expect(portableRoot(27.0, 3), 3.0);
    expect(portableRoot(1.0, 3), 1.0);
    expect(portableRoot(1e-9, 3), 0.001);
  });

  test('the root raised back gives the argument, to a few ulps', () {
    // Mutation: stop Newton's method one step early (`next <= y`). The fifth
    // root of 0.0031 is then a hair above the root, and the power comes out
    // high in the fifteenth place.
    for (final x in <double>[0.0031, 0.04, 0.18, 0.5, 0.99, 1.7, 12.5]) {
      final fifth = portableRoot(x, 5);
      final cube = portableRoot(x, 3);
      expect(
        fifth * fifth * fifth * fifth * fifth,
        closeTo(x, x * 1e-15),
        reason: 'fifth root of $x',
      );
      expect(cube * cube * cube, closeTo(x, x * 1e-15), reason: 'cube $x');
    }
  });

  test('the curve rises and never steps back', () {
    var previous = -1.0;
    for (var k = 0; k <= 4096; k++) {
      final encoded = toSrgb(k / 4096.0);
      expect(encoded, greaterThan(previous), reason: '$k / 4096');
      previous = encoded;
    }
  });

  test('every byte survives decoding and encoding again', () {
    for (var k = 0; k <= 255; k++) {
      final c = k / 255.0;
      expect(toSrgb(toLinear(c)), closeTo(c, 1e-15), reason: 'byte $k');
    }
  });

  test('the values are these, to the bit', () {
    // Recorded once, and what a platform that disagrees would fail. A linear
    // half encodes to the paint program's 191; an 18% grey to its 125.
    expect(portablePow5Over12(0.5), 0.749153538438341);
    expect(portablePow5Over12(0.18), 0.4894370895738784);
    expect(portablePow12Over5(0.5), 0.18946457081379975);
    expect(portablePow12Over5(0.7354), 0.47825189692779857);
  });
}
