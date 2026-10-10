/// A world's properties: its defaults, its derived air, and its file.
///
///     dart test test/world_properties_test.dart
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the standard world is the standard numbers, to the bit', () {
    // Mutation: compare the f32 gravity with `-standardGravity` (the double)
    // in `gravityMagnitude`, which is what it did — 9.8100004196 comes back.
    final world = WorldProperties.standard;
    expect(world.gravityMagnitude, standardGravity);
    expect(world.airDensity, standardAirDensity);
    expect(world.speedOfSound, standardSpeedOfSound);
    expect(world.medium, 'f3d.air');
  });

  test('the air follows its temperature and pressure', () {
    final thin = WorldProperties(airPressure: standardAtmosphere / 2);
    expect(thin.airDensity, closeTo(standardAirDensity / 2, 1e-12));
    final cold = WorldProperties(airTemperature: 273.15);
    // 343 · √(273.15 / 293.15). The textbook 331.3 belongs to air that is
    // 343.2 at 20 °C; the engine's air is 343.0 there, to the bit.
    // Mutation: scale by T instead of √T — 319.6 comes back.
    expect(cold.speedOfSound, closeTo(331.093, 1e-3));
    // Said outright, it is what it was told.
    expect(WorldProperties(airDensity: 0.02).airDensity, 0.02);
  });

  test('the medium is read through the catalogue', () {
    final catalogue = MaterialCatalog.builtIn();
    expect(
      WorldProperties.standard.mediumDensity(catalogue),
      standardAirDensity,
    );
    expect(
      WorldProperties(medium: 'f3d.seawater').mediumDensity(catalogue),
      Materials.seawater.density,
    );
    expect(
      () => WorldProperties(medium: 'reef.brine').mediumDensity(catalogue),
      throwsA(isA<UnknownMaterialException>()),
    );
  });

  test('a world survives its file', () {
    final moon = WorldProperties(
      gravity: Vector3(0.0, -1.62, 0.0),
      airPressure: 1e-3,
      airDensity: 1e-12,
      wind: Vector3(1.0, 0.0, 0.0),
    );
    expect(WorldProperties.fromJson(moon.toJson()), moon);
  });

  test('a world read from before 1.0 keeps reading, its step rate aside', () {
    // A snapshot or a level written while a world carried its step rate.
    // The rate is the loop's (`WorldTiming`) now, so the key is passed over
    // rather than refused.
    final read = WorldProperties.fromJson(<String, Object?>{
      'gravity': <double>[0.0, -1.62, 0.0],
      'stepRate': 120.0,
    });
    expect(read.gravity, Vector3(0.0, -1.62, 0.0));
    expect(read.toJson().containsKey('stepRate'), isFalse);
  });

  test('a world hands out copies, so nobody bends its gravity', () {
    final world = WorldProperties(gravity: Vector3(0.0, -9.81, 0.0));
    world.gravity.scale(2.0);
    world.wind.setValues(5.0, 0.0, 0.0);
    expect(world.gravity, Vector3(0.0, -9.81, 0.0));
    expect(world.wind, Vector3.zero());
  });

  test("a level's scalar gravity reads as down y, over the game's world", () {
    final game = WorldProperties(gravity: Vector3(0.0, -24.0, 0.0));
    final level = WorldProperties.fromJson(<String, Object?>{
      'gravity': 1.62,
    }, base: game);
    expect(level.gravity, Vector3(0.0, -1.62, 0.0));
    expect(
      WorldProperties.fromJson(const <String, Object?>{}, base: game),
      game,
    );
    expect(
      () => WorldProperties.fromJson(<String, Object?>{'gravity': -3}),
      throwsA(isA<WorldPropertiesFormatException>()),
    );
  });
}
