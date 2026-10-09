/// The floating origin of a collision world: one call moves it, and it is
/// part of a snapshot, restored before the bodies written in it.
///
///     dart test test/origin_test.dart
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('moving the origin moves every collider the other way', () {
    // Mutation: shift by the new origin rather than by the difference — a
    // second move lands the wall twice as far.
    final world = CollisionWorld();
    final wall = Collider(
      shape: CollisionBox(Vector3(1.0, 1.0, 1.0)),
      position: Vector3(100.0, 0.0, 0.0),
    );
    world.add(wall);
    world.moveOriginTo(const WorldPosition(60.0, 0.0, 0.0));
    world.moveOriginTo(const WorldPosition(90.0, 0.0, 0.0));
    expect(world.origin, const WorldPosition(90.0, 0.0, 0.0));
    expect(wall.position.x, closeTo(10.0, 1e-9));
  });

  test('the origin part puts the origin back first, carrying the level', () {
    // A body's snapshot is a position relative to the origin it was taken
    // under. Mutation: restore the origin by setting the number alone — the
    // level's wall stays in the frame of the later origin.
    final world = CollisionWorld();
    final wall = Collider(
      shape: CollisionBox(Vector3(1.0, 1.0, 1.0)),
      position: Vector3(100.0, 0.0, 0.0),
    );
    world.add(wall);
    final part = world.originPart;
    expect(part.restoresFirst, isTrue);
    final captured = part.capture();

    world.moveOriginTo(const WorldPosition(50.0, 0.0, 0.0));
    expect(wall.position.x, closeTo(50.0, 1e-9));

    part.restore(captured, part.version);
    expect(world.origin, WorldPosition.origin);
    expect(wall.position.x, closeTo(100.0, 1e-9));
  });
}
