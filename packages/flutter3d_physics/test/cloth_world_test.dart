/// A cloth in a world: it falls by the world's gravity and its world's wind
/// blows it.
///
///     dart test test/cloth_world_test.dart
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The mean z of a hanging sheet after two seconds under [settings].
double _meanZ(ClothSettings settings) {
  final sheet = ClothMesh.grid(cols: 8, rows: 8, height: 1.0);
  for (var i = 0; i < 120; i++) {
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
    expect(settings.gravity, 1.62);
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
    expect(windy, greaterThan(still + 0.01));
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
}
