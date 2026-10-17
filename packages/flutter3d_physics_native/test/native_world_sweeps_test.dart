/// The core sweeping a world's shapes for `CollisionWorld.sweep`, as the
/// reference sweeps them.
///
///     flutter test test/native_world_sweeps_test.dart
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A floor, a wall standing on it, and the world's own walk or the core.
({CollisionWorld world, Collider floor, Collider wall, NativeDynamics? core})
_room({required bool native}) {
  final world = CollisionWorld();
  final floor = world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
  final wall = world.addBox(Vector3(4.0, 1.0, 0.0), Vector3(1.0, 2.0, 6.0));
  final core = native ? NativeDynamics(world: world, castsRays: true) : null;
  world.update();
  return (world: world, floor: floor, wall: wall, core: core);
}

void main() {
  final shapes = <String, CollisionShape>{
    'box': CollisionBox(Vector3(0.4, 0.4, 0.4)),
    'sphere': CollisionSphere(0.4),
    'capsule': CollisionCapsule(radius: 0.3, halfHeight: 0.4),
  };

  for (final MapEntry(key: name, value: shape) in shapes.entries) {
    test('a $name dropped and thrown meets what the reference meets, as far '
        'along', () {
      final dart = _room(native: false);
      final core = _room(native: true);
      addTearDown(core.core!.dispose);
      expect(core.world.sweeps, isA<NativeWorldSweeps>());
      for (final (from, by) in <(Vector3, Vector3)>[
        (Vector3(0.0, 3.0, 0.0), Vector3(0.0, -5.0, 0.0)),
        (Vector3(0.0, 1.0, 0.0), Vector3(6.0, 0.0, 0.0)),
        (Vector3(0.0, 1.0, 0.0), Vector3(-6.0, 0.0, 0.0)),
      ]) {
        final a = SweepHit();
        final b = SweepHit();
        final metA = dart.world.sweep(shape, from, by, a);
        final metB = core.world.sweep(shape, from, by, b);
        expect(metB, metA, reason: '$from by $by');
        if (!metA) continue;
        expect(b.fraction, closeTo(a.fraction, 1e-3), reason: '$from by $by');
        expect(b.normal.dot(a.normal), closeTo(1.0, 1e-3));
        // The same wall, named back as the world's own collider.
        expect(
          b.collider == core.wall,
          a.collider == dart.wall,
          reason: '$from by $by',
        );
      }
    });
  }

  test('a shape that starts inside meets nothing, as the reference says', () {
    final core = _room(native: true);
    addTearDown(core.core!.dispose);
    final hit = SweepHit();
    // Mutation: reporting the overlap as a hit at nought, which would hold a
    // body a micrometre into a wall there for good.
    expect(
      core.world.sweep(
        CollisionBox(Vector3(0.4, 0.4, 0.4)),
        Vector3(4.0, 1.0, 0.0),
        Vector3(1.0, 0.0, 0.0),
        hit,
      ),
      isFalse,
    );
  });

  test('a sweep with a filter is the world\'s own, and a mask is kept', () {
    final core = _room(native: true);
    addTearDown(core.core!.dispose);
    final shape = CollisionBox(Vector3(0.4, 0.4, 0.4));
    var asked = 0;
    final hit = SweepHit();
    // Mutation: sending a filtered sweep to the core, which cannot ask it.
    core.world.sweep(
      shape,
      Vector3(0.0, 3.0, 0.0),
      Vector3(0.0, -5.0, 0.0),
      hit,
      allow: (SweptContact contact) {
        asked++;
        return true;
      },
    );
    expect(asked, greaterThan(0));
    expect(
      core.world.sweep(
        shape,
        Vector3(0.0, 3.0, 0.0),
        Vector3(0.0, -5.0, 0.0),
        hit,
        mask: 0,
      ),
      isFalse,
    );
    core.core!.dispose();
    expect(core.world.sweeps, isNull);
  });
}
