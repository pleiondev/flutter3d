/// How much of a sound the walls let through.
///
///     flutter test test/sound_occlusion_test.dart
///
/// The three-room level again: a doorway between A and B, a wall between B
/// and C. A sound heard through the doorway is clear, through one wall it is
/// halved, through two it is quartered, and past four it stops falling.
library;

import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x, double y, double z, double sx, double sy, double sz) =>
    Brush(centre: Vector3(x, y, z), size: Vector3(sx, sy, sz));

/// Rooms A (x 0..8), B (x 10..18) and C (x 20..28); a doorway at z 3..5
/// between A and B, a solid wall between B and C.
Level _rooms() => Level(
  brushes: <Brush>[
    _box(14.0, -0.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 4.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 2.0, -0.5, 30.0, 4.0, 1.0),
    _box(14.0, 2.0, 8.5, 30.0, 4.0, 1.0),
    _box(-0.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(28.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(9.0, 2.0, 1.5, 2.0, 4.0, 3.0),
    _box(9.0, 2.0, 6.5, 2.0, 4.0, 3.0),
    _box(19.0, 2.0, 4.0, 2.0, 4.0, 8.0),
  ],
);

CollisionWorld _world() {
  final world = CollisionWorld();
  _rooms().addTo(world);
  world.update();
  return world;
}

void main() {
  test('a sound through the doorway is clear', () {
    final occlusion = SoundOcclusion(_world());

    expect(
      occlusion.between(Vector3(14.0, 1.5, 4.0), Vector3(2.0, 1.5, 4.0)),
      1.0,
    );
    expect(occlusion.lastObstacles, 0);
  });

  test('one wall halves it, two quarter it', () {
    final occlusion = SoundOcclusion(_world());

    // B to A past the doorway's edge: through the wall at x 8..10.
    expect(
      occlusion.between(Vector3(14.0, 1.5, 1.0), Vector3(2.0, 1.5, 1.0)),
      0.5,
    );
    expect(occlusion.lastObstacles, 1);
    // C to A: the B–C wall and then the A–B wall.
    expect(
      occlusion.between(Vector3(24.0, 1.5, 1.0), Vector3(2.0, 1.5, 1.0)),
      0.25,
    );
    expect(occlusion.lastObstacles, 2);
  });

  test('is the same from either end', () {
    // Pure, and symmetric: a replay has to sound the way the run did, and
    // the ear and the torch trading places changes nothing about the walls.
    final occlusion = SoundOcclusion(_world());
    final there = occlusion.between(
      Vector3(24.0, 1.5, 1.0),
      Vector3(2.0, 1.5, 1.0),
    );
    final back = occlusion.between(
      Vector3(2.0, 1.5, 1.0),
      Vector3(24.0, 1.5, 1.0),
    );
    expect(back, there);
  });

  test('stops falling at the floor', () {
    // Through the floor, the ceiling and every wall a long diagonal crosses:
    // still audible, faintly, rather than switched off.
    final occlusion = SoundOcclusion(_world(), maxObstacles: 2);

    expect(
      occlusion.between(Vector3(24.0, 1.5, 1.0), Vector3(2.0, 1.5, 1.0)),
      0.25,
      reason: 'two obstacles counted, the cap not yet reached',
    );
    final capped = SoundOcclusion(_world(), floor: 0.3);
    expect(
      capped.between(Vector3(24.0, 1.5, 1.0), Vector3(2.0, 1.5, 1.0)),
      0.3,
    );
  });

  test('a sound at the ear is clear', () {
    final occlusion = SoundOcclusion(_world());
    expect(
      occlusion.between(Vector3(2.0, 1.5, 4.0), Vector3(2.0, 1.5, 4.0)),
      1.0,
    );
  });
}
