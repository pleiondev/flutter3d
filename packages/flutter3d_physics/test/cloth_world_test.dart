/// A cloth in a world: it falls by the world's gravity and its world's wind
/// blows it.
///
///     dart test test/cloth_world_test.dart
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The mean z of a hanging sheet after ten seconds under [settings], long
/// enough for its swing to die out.
double _meanZ(ClothSettings settings) {
  final sheet = ClothMesh.grid(cols: 8, rows: 8, height: 1.0);
  for (var i = 0; i < 600; i++) {
    stepCloth(sheet, settings, 1 / 60);
  }
  final p = sheet.positions;
  var sum = 0.0;
  for (var i = 2; i < p.length; i += 3) {
    sum += p[i];
  }
  return sum / (p.length ~/ 3);
}

void main() {
  test("a sheet takes its world's gravity and wind", () {
    final storm = WorldProperties(
      gravity: Vector3(0.0, -1.62, 0.0),
      wind: Vector3(0.0, 0.0, 6.0),
    );
    final settings = const ClothSettings().inWorld(storm);
    // The world keeps its gravity in a `Vector3`, an f32: 1.62 is
    // 1.6200000048 there, and the sheet takes the world's number exactly.
    expect(settings.gravity, storm.gravityMagnitude);
    expect(settings.gravity, closeTo(1.62, 1e-7));
    expect(settings.wind.velocityZ, 6.0);
    // The drag the sheet had is kept: the world says how the air moves, the
    // sheet how much it catches.
    expect(settings.wind.drag, const WindSettings().drag);
  });

  test("the world's wind blows the sheet", () {
    // Mutation: drop the wind from `inWorld` and the two sheets hang alike.
    final still = _meanZ(
      const ClothSettings().inWorld(WorldProperties.standard),
    );
    final windy = _meanZ(
      const ClothSettings().inWorld(
        WorldProperties(wind: Vector3(0.0, 0.0, 6.0)),
      ),
    );
    expect(still, closeTo(0.0, 1e-6));
    // At rest, a sheet under a uniform load across it and its weight down
    // hangs straight at tan θ = F / W, and its mean z is the mean depth
    // (0.35 m) times that. F = drag · 6 m/s · area, the area 0.49 m² less
    // half the top strip, whose pinned corners take their share; W is the
    // 56 free particles of 0.05 kg. It measures 0.0098 against 0.0104.
    const area = 0.49 - 0.035;
    final lean = 0.35 * (0.3 * 6.0 * area) / (56 * 0.05 * standardGravity);
    expect(windy, closeTo(lean, 0.1 * lean));
  });

  test('the standard world changes nothing, to the bit', () {
    final sheet = ClothMesh.grid(cols: 4, rows: 4, height: 1.0);
    final other = ClothMesh.grid(cols: 4, rows: 4, height: 1.0);
    for (var i = 0; i < 30; i++) {
      stepCloth(sheet, const ClothSettings(), 1 / 60);
      stepCloth(
        other,
        const ClothSettings().inWorld(WorldProperties.standard),
        1 / 60,
      );
    }
    expect(other.positions, sheet.positions);
  });

  test("the wind's drag goes with the density of the world's air", () {
    // Mutation: leave the air density out of `inWorld`, or out of the
    // solver's drag, and the thin air leans the sheet as far as the
    // standard air does.
    final thin = WorldProperties(
      wind: Vector3(0.0, 0.0, 6.0),
      airDensity: 0.5 * standardAirDensity,
    );
    final settings = const ClothSettings().inWorld(thin);
    expect(settings.wind.airDensity, thin.airDensity);
    expect(settings.wind.effectiveDrag, 0.5 * const WindSettings().drag);
    expect(const WindSettings().effectiveDrag, const WindSettings().drag);
    final standard = _meanZ(
      const ClothSettings().inWorld(
        WorldProperties(wind: Vector3(0.0, 0.0, 6.0)),
      ),
    );
    // Small leans are linear in the load: half the air, half the lean.
    expect(_meanZ(settings), closeTo(0.5 * standard, 0.05 * standard));
  });

  test("a sheet of a material slides by the material's friction", () {
    final settings = const ClothSettings().inWorld(
      WorldProperties.standard,
      material: Materials.cotton,
    );
    expect(settings.friction, Materials.cotton.mechanical!.friction!.value);
    // A material that says none keeps the friction the settings had.
    expect(
      const ClothSettings(
        friction: 0.25,
      ).inWorld(WorldProperties.standard, material: Materials.air).friction,
      0.25,
    );
    // And inWorld twice is the last world's, not both.
    final thin = WorldProperties(airDensity: 0.5);
    expect(
      const ClothSettings()
          .inWorld(thin)
          .inWorld(WorldProperties.standard)
          .wind
          .effectiveDrag,
      const WindSettings().drag,
    );
  });

  test("a grid's particles weigh the material's density", () {
    final mass = ClothMesh.particleMassOf(
      Materials.cotton,
      thickness: 5e-4,
      spacing: 0.1,
    );
    expect(mass, closeTo(80.0 * 5e-4 * 0.01, 1e-15));
  });

  test('under the accurate profile the wind leans a sheet as it does on the '
      'fixed step', () {
    // The same statics either way: the profile changes how the swing is
    // followed, not where the sheet comes to rest.
    final windy = WorldProperties(wind: Vector3(0.0, 0.0, 6.0));
    final fixed = _meanZ(const ClothSettings().inWorld(windy));
    final accurate = _meanZ(
      const ClothSettings(profile: SimulationProfile.accurate).inWorld(windy),
    );
    expect(accurate, closeTo(fixed, 0.1 * fixed));
  });
}
