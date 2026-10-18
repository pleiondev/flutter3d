/// The trigonometry a turning body is allowed, asked two questions.
///
///     dart test test/portable_math_test.dart
///
///  1. **The same bits every time and everywhere.** One recorded digest per
///     function over a fixed sweep of arguments. A second answer appearing on
///     some platform is the failure the library exists to rule out.
///  2. **The right answer.** The same sweep against `dart:math`, in units in
///     the last place. Both platforms agreeing on a wrong number would pass
///     every digest.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('the same answer everywhere', () {
    // Recorded on macOS-arm64 under the VM, 2026-10-01, where the same sweep
    // through `flutter3d_sim`'s `Portable` answered the same bits for every
    // one of the 20000 arguments of every function.
    //
    // Mutation: a coefficient in either kernel changed in its last digit, or
    // `_quarterTurns` taking π/2 in one piece, changes every one of these.
    for (final row in <(String, int, double Function(int))>[
      ('sin', 1047661232, (int i) => Portable.sin(_a[i])),
      ('cos', 19596382, (int i) => Portable.cos(_a[i])),
      ('atan', 3618538760, (int i) => Portable.atan(_a[i])),
      ('atan2', 273388763, (int i) => Portable.atan2(_a[i], _b[i])),
      ('asin', 1248226849, (int i) => Portable.asin(_a[i].abs() % 1.0)),
      ('acos', 730462323, (int i) => Portable.acos(_a[i].abs() % 2.0 - 1.0)),
    ]) {
      final (name, expected, at) = row;
      test('$name gives one answer, not one per platform', () {
        expect(
          _digest(<double>[for (var i = 0; i < _sweep; i++) at(i)]),
          expected,
          reason:
              'Portable.$name answered differently here than where this was '
              'recorded. Everything in it is IEEE arithmetic over the same '
              'bits, so that is an edit that changed its answers or a platform '
              'whose `*` is not the specification\'s. Either is news.',
        );
      });
    }

    test('sinCos agrees with sin and cos taken apart', () {
      // Mutation: a quadrant table in `sinCos` with two rows swapped passes
      // every digest above and turns an axis the wrong way a quarter of the
      // time.
      for (var i = 0; i < _sweep; i++) {
        final both = Portable.sinCos(_a[i]);
        expect(both.sin, Portable.sin(_a[i]));
        expect(both.cos, Portable.cos(_a[i]));
      }
    });
  });

  group('and the right answer', () {
    // Mutation: any coefficient typed wrong in its fourth digit — which no
    // digest notices, because it is wrong the same way everywhere.
    for (final row
        in <(String, double Function(double), double Function(double))>[
          ('sin', Portable.sin, math.sin),
          ('cos', Portable.cos, math.cos),
          ('atan', Portable.atan, math.atan),
        ]) {
      final (name, ours, theirs) = row;
      test('$name is within two ulp of dart:math', () {
        final (worst, at) = _worst(
          _sweep,
          (int i) => (ours(_a[i]), theirs(_a[i]), _a[i]),
        );
        expect(worst, lessThanOrEqualTo(2.0), reason: '$name at $at');
      });
    }

    test('atan2 is within two ulp of dart:math, in all four quadrants', () {
      final (worst, at) = _worst(
        _sweep,
        (int i) =>
            (Portable.atan2(_a[i], _b[i]), math.atan2(_a[i], _b[i]), _a[i]),
      );
      expect(worst, lessThanOrEqualTo(2.0), reason: 'atan2 at $at');
      // The signed zeros and infinities, which are conventions rather than
      // limits and are where a hand port usually slips.
      for (final (y, x) in <(double, double)>[
        (0.0, -1.0),
        (-0.0, -1.0),
        (0.0, 1.0),
        (1.0, 0.0),
        (-1.0, 0.0),
        (double.infinity, double.infinity),
        (double.infinity, double.negativeInfinity),
        (1.0, double.negativeInfinity),
      ]) {
        expect(Portable.atan2(y, x), math.atan2(y, x), reason: 'atan2($y, $x)');
      }
    });

    test('asin is within four ulp of dart:math, including at the ends', () {
      final (worst, at) = _worst(_sweep + 4, (int i) {
        final x = i < _sweep
            ? _a[i].abs() % 1.0
            : const <double>[1.0, -1.0, 0.9999999999, -0.9999999999][i -
                  _sweep];
        return (Portable.asin(x), math.asin(x), x);
      });
      expect(worst, lessThanOrEqualTo(4.0), reason: 'asin at $at');
    });

    test('acos is within two ulp of dart:math, including near one', () {
      // Near one is where a joint at rest sits, and where `π/2 - asin(x)`
      // would cancel away nearly every digit.
      //
      // Mutation: `acos` written as `π/2 - asin(x)` is out by thousands of
      // ulp at 0.9999999999.
      const ends = <double>[1.0, -1.0, 0.9999999999, -0.9999999999, 0.0];
      final (worst, at) = _worst(_sweep + ends.length, (int i) {
        final x = i < _sweep ? _a[i].abs() % 2.0 - 1.0 : ends[i - _sweep];
        return (Portable.acos(x), math.acos(x), x);
      });
      expect(worst, lessThanOrEqualTo(2.0), reason: 'acos at $at');
    });

    test('and an argument it cannot answer is NaN, not a throw', () {
      expect(Portable.sin(double.infinity), isNaN);
      expect(Portable.cos(double.nan), isNaN);
      expect(Portable.acos(1.5), isNaN);
      expect(Portable.asin(-1.5), isNaN);
      expect(Portable.sinCos(double.infinity).sin, isNaN);
    });
  });
}

/// The largest distance in ulp across [count] cases, and the argument it was
/// found at.
(double, double) _worst(int count, (double, double, double) Function(int) at) {
  return Iterable<int>.generate(count).map(at).fold<(double, double)>(
    (0.0, 0.0),
    (worst, row) {
      final (ours, theirs, x) = row;
      final error = _ulpsApart(ours, theirs);
      return error > worst.$1 ? (error, x) : worst;
    },
  );
}

/// How far apart [a] and [b] are, in units of the last place at [b].
///
/// A distance over an ulp rather than a difference of bit patterns: those are
/// near 2^62 and their difference taken in a double rounds to a multiple of
/// 1024, which is what an instrument measuring itself looks like.
double _ulpsApart(double a, double b) {
  if (a == b) return 0.0;
  if (a.isNaN && b.isNaN) return 0.0;
  if (a.isNaN || b.isNaN || a.isInfinite || b.isInfinite) {
    return double.infinity;
  }
  return (a - b).abs() / _ulpSize(b);
}

/// The gap between [x] and the next double away from zero, found by adding one
/// to the mantissa — through `ByteData` in halves, because a browser's integers
/// stop being exact at 2^53.
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

/// FNV-1a over the eight bytes of every double, as an unsigned 32-bit number.
///
/// The multiply by the FNV prime is split as `2^24 + 403` so no product passes
/// 2^53: on the web an integer is a double, and a product past that rounds —
/// the digest would then be a property of the platform it was checking.
int _digest(List<double> values) {
  final bytes = ByteData(8);
  return values.fold<int>(0x811C9DC5, (hash, value) {
    bytes.setFloat64(0, value);
    return Iterable<int>.generate(8).fold<int>(hash, (h, i) {
      final mixed = h ^ bytes.getUint8(i);
      return ((mixed % 256) * 16777216 + mixed * 403) % 4294967296;
    });
  });
}

const int _sweep = 20000;

/// Arguments in four bands — a unit interval, two turns either way, a thousand
/// radians, and a ten-thousandth — drawn from a golden-ratio sequence.
///
/// **Built from double arithmetic alone**, so the arguments are the same bits
/// on every platform before any function is asked about them: `%` on doubles
/// is exact, and so is a product rounded once.
List<double> _sweepArguments(double offset) => <double>[
  for (var i = 0; i < _sweep; i++)
    switch (((i + offset) * 0.6180339887498949) % 1.0 * 2.0 - 1.0) {
      final u => switch (i % 4) {
        0 => u,
        1 => u * math.pi * 2.0,
        2 => u * 1000.0,
        _ => u * 1e-4,
      },
    },
];

final List<double> _a = _sweepArguments(0.5);
final List<double> _b = _sweepArguments(0.25);
