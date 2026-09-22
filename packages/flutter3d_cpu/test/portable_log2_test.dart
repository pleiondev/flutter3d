// What a mip level is chosen by, and the reason it cannot be `math.log`.
//
// **Nothing here compares against `dart:math`.** That is the function being
// replaced, and it is the one whose answers differ between platforms — a test
// holding this to libm would pass on the machine the expectations were written
// on and mean nothing anywhere else. What is asserted instead is what the
// specification pins: the exact answers at powers of two, monotonicity, the
// inverse relation against exact multiplication, and a handful of values
// written out to the last bit.
import 'package:flutter3d_cpu/src/portable_log2.dart';
import 'package:test/test.dart';

void main() {
  test('a power of two lands exactly on its own exponent', () {
    // The case that matters most: the floor of the answer is the level a
    // sample reads, so a power of two answering 2.9999999999999996 rather
    // than 3.0 is a texture one level too sharp, along the whole band of the
    // picture where the footprint happens to sit there.
    for (var e = -60; e <= 60; e++) {
      var x = 1.0;
      for (var i = 0; i < e.abs(); i++) {
        x = e > 0 ? x * 2.0 : x / 2.0;
      }
      expect(portableLog2(x), e.toDouble(), reason: '2^$e');
    }
  });

  test('doubling an argument adds one, to the last bit', () {
    // The series term is literally the same number for `x` and `2x` — the
    // mantissa does not change, only the exponent read off the bits — so this
    // is as close to exact as the final addition allows. Five of the six
    // below are exact; `1.9999` comes back half an ulp short, because adding
    // the same series to 0 and to 1 rounds in two different places.
    for (final x in <double>[1.3, 1.9999, 3.7, 17.25, 1023.5, 40967.125]) {
      expect(
        portableLog2(x * 2.0) - portableLog2(x),
        closeTo(1.0, 2.3e-16),
        reason: '$x',
      );
    }
  });

  test('it rises with its argument, with no step backwards', () {
    var previous = double.negativeInfinity;
    for (var i = 1; i <= 20000; i++) {
      final here = portableLog2(i / 7.0);
      expect(here, greaterThan(previous), reason: 'at ${i / 7.0}');
      previous = here;
    }
  });

  test('the values a footprint actually asks for, to the last bit', () {
    // Written out rather than computed, so a change to the series has to be
    // looked at rather than absorbed. These are this function's own answers,
    // not libm's: three of the six sit one unit in the last place away from
    // what the platform returns, which is the accuracy claimed and no more.
    expect(portableLog2(1.0), 0.0);
    expect(portableLog2(1.5), 0.5849625007211563);
    expect(portableLog2(3.0), 1.5849625007211563);
    expect(portableLog2(10.0), 3.321928094887362);
    expect(portableLog2(100.0), 6.643856189774724);
    expect(portableLog2(512.0), 9.0);
  });

  test('a mantissa near either end of its range is equally accurate', () {
    // The halving inside is what makes this true: without it `t` runs to a
    // third at the top of the range and the series falls further short of the
    // last bit there than it does at the bottom.
    expect(portableLog2(1.9999999999), closeTo(0.9999999999278653, 1e-16));
    expect(portableLog2(1.0000000001), closeTo(1.4426951601859516e-10, 1e-25));
  });

  test('it answers rather than throws where a caller never goes', () {
    expect(portableLog2(0.0), double.negativeInfinity);
    expect(portableLog2(-1.0), double.negativeInfinity);
    expect(portableLog2(double.nan).isNaN, isTrue);
    expect(portableLog2(double.infinity), double.infinity);
  });

  test('a subnormal keeps its exponent', () {
    // 2^-1060, well below the smallest normal double. The scaling branch is
    // the only way this answers anything but negative infinity.
    var x = 1.0;
    for (var i = 0; i < 1060; i++) {
      x /= 2.0;
    }
    expect(x, greaterThan(0.0));
    expect(portableLog2(x), -1060.0);
  });
}
