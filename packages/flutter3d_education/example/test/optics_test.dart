import 'dart:math' as math;

import 'package:chemlab/chemlab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The light that fell across [cut], in the units of an empty bench.
double _total(List<double> channel, OpticsCut cut) =>
    channel.fold(0.0, (a, b) => a + b) * 2.0 * cut.halfWidth / cut.bins;

OpticsCut _cut({double? liquid, Vector3? absorption, double reach = 0.4}) =>
    traceCut(
      outer: 0.08,
      wall: 0.004,
      liquid: liquid,
      glassIndex: 1.5,
      liquidIndex: 1.33,
      liquidAbsorption: absorption ?? Vector3.zero(),
      elevation: 52 * math.pi / 180,
      reach: reach,
      halfWidth: 0.3,
    );

void main() {
  test('nothing in the way leaves the bench as lit as it was', () {
    final cut = traceCut(
      outer: null,
      wall: 0.004,
      liquid: null,
      glassIndex: 1.5,
      liquidIndex: 1.33,
      liquidAbsorption: Vector3.zero(),
      elevation: 0.9,
      reach: 0.4,
      halfWidth: 0.3,
    );
    for (var i = 2; i < cut.bins - 2; i++) {
      expect(cut.red[i], closeTo(1.0, 0.02));
    }
  });

  test('an empty tube loses only what its four surfaces reflect', () {
    // Clear glass absorbs nothing here, so what is missing from the bench is
    // what Fresnel turned back: a few per cent at each of four surfaces, and
    // more at the grazing edges. Mutation: drop the reflection, and nothing
    // is missing; reflect at every surface twice, and too much is.
    final cut = _cut();
    final missing = 0.6 - _total(cut.red, cut);
    expect(missing, greaterThan(0.16 * 0.08));
    expect(missing, lessThan(0.16 * 0.5));
  });

  test('a filled tube gathers light into a line and darkens its sides', () {
    // Water inside the glass makes the cut a lens: beams through the middle
    // cross and spread, and the bench under the tube's shadow has places
    // brighter than an empty bench and places much darker. Mutation: leave
    // the liquid's index at one, and nothing gathers.
    final cut = _cut(liquid: 0.074, reach: 0.12);
    final peak = cut.red.reduce(math.max);
    final low = cut.red.reduce(math.min);
    expect(peak, greaterThan(1.3));
    expect(low, lessThan(0.5));
  });

  test('a coloured solution colours what it lets through', () {
    // Copper sulphate keeps blue and takes red. Mutation: apply one
    // absorption to all three channels, and the ratio stays one.
    final blue = absorptionFor(Vector3(0.2, 0.45, 0.95), 0.08);
    final cut = _cut(liquid: 0.074, absorption: blue);
    // Compared as a difference: both lose what Fresnel reflects and what the
    // liquid spreads past the edge of the window after its focus, and only
    // red is taken by the solution as well.
    final takenRed = 0.6 - _total(cut.red, cut);
    final takenBlue = 0.6 - _total(cut.blue, cut);
    expect(takenRed - takenBlue, greaterThan(0.03));
  });

  test('the radius of a profile is read where the profile reaches', () {
    final profile = [Vector2(0, 0), Vector2(0.2, 0), Vector2(0.2, 0.4)];
    expect(radiusAt(profile, 0.2), closeTo(0.2, 1e-6));
    expect(radiusAt(profile, 0.5), isNull);
  });
}
