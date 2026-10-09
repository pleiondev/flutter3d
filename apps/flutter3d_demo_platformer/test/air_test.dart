/// The sky over the levels and the fog in them — `air.dart`.
///
///     flutter test test/air_test.dart
library;

import 'package:flutter3d_demo_platformer/src/air.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'climbing.dart' show shippedLevel;

void main() {
  test('the sky is lit by the sun the level is lit by', () {
    // Every shipped level is lit from 58° up, so its sky is a day's: blue
    // overhead, the sun where the light on the stones comes from.
    //
    // Mutation: put the sun along the light's direction rather than back up
    // it, and it stands under the horizon — a night sky over a lit level,
    // nearly black overhead.
    for (final asset in <String>[
      'assets/levels/first_steps.json',
      'assets/levels/ascent.json',
      'assets/levels/cisterns.json',
      'assets/levels/foundry.json',
      'assets/levels/spire.json',
    ]) {
      final level = shippedLevel(asset);
      final sky = levelSky(level);
      final light = level.lights.firstWhere(
        (l) => l.type == LevelLightType.directional,
      );
      expect(sky.enabled, isTrue);
      expect(sky.resolvedPhysical, isNotNull, reason: '$asset: no air');
      expect(
        sky.resolvedDirectionToSun.dot(-light.direction.normalized()),
        closeTo(1.0, 1e-6),
        reason: '$asset: the sun is not where its light comes from',
      );
      final overhead = sky.sample(Vector3(0.0, 1.0, 0.0));
      expect(overhead.z, greaterThan(overhead.x), reason: '$asset: not blue');
      expect(overhead.z, greaterThan(0.1), reason: '$asset: not day');
    }
  });

  test('the fog is the level\'s own, and thins upwards', () {
    // Mutation: leave the fall-off at nought, and the haze over the pits is
    // as thick at the top of the spire.
    final level = shippedLevel('assets/levels/cisterns.json');
    final fog = levelFog(level);
    expect(fog.resolvedColor, level.fogColor);
    expect(fog.density, level.fogDensity);
    expect(fog.heightFalloff, greaterThan(0.0));
    expect(fog.densityAt(14.0), lessThan(fog.densityAt(0.0) * 0.6));
  });
}
