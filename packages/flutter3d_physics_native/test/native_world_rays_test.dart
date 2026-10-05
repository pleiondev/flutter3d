// A world's rays cast by the core — P9: `CollisionWorld.raycast` with the
// world's `rays` set by a `NativeDynamics(castsRays: true)`, beside the same
// world's own walk. Every ray that does not ask for triggers is the core's:
// the same collider met at the same distance, a mover where it is this
// step, what is ignored and masked away not met; a ray that asks for
// triggers is the world's own.
//
//     dart test test/native_world_rays_test.dart

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late CollisionWorld world;
  late NativeDynamics dynamics;
  late Collider floor, wall, door, sensor;
  setUp(() {
    world = CollisionWorld();
    floor = world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    wall = world.addBox(Vector3(5.0, 1.0, 0.0), Vector3(0.5, 2.0, 4.0));
    door = world.add(
      Collider(
        shape: CollisionBox(Vector3(0.1, 1.0, 1.0)),
        position: Vector3(2.0, 1.0, 10.0),
        kind: ColliderKind.kinematic,
        layer: 1 << 2,
      ),
    );
    sensor = world.add(
      Collider(
        shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
        position: Vector3(-3.0, 1.0, 0.0),
        kind: ColliderKind.trigger,
      ),
    );
    // Indexed, as a game's step indexes it; the core has not stepped yet.
    world.update();
    dynamics = NativeDynamics(world: world, castsRays: true);
    addTearDown(dynamics.dispose);
  });

  /// [world]'s answer, through the core and through its own walk.
  (RayHit, RayHit) both(
    Vector3 origin,
    Vector3 direction, {
    int mask = Layers.all,
    Collider? ignore,
  }) {
    final core = RayHit();
    world.raycast(origin, direction, 50.0, core, mask: mask, ignore: ignore);
    final rays = world.rays;
    world.rays = null;
    final own = RayHit();
    world.raycast(origin, direction, 50.0, own, mask: mask, ignore: ignore);
    world.rays = rays;
    return (core, own);
  }

  test('the world says who casts its rays', () {
    expect(world.rays, isA<NativeWorldRays>());
    dynamics.dispose();
    expect(world.rays, isNull);
    dynamics = NativeDynamics(world: world);
  });

  test('a shot meets the wall the walk meets, as far', () {
    final (core, own) = both(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0));
    expect(core.collider, same(wall));
    expect(own.collider, same(wall));
    expect(core.distance, closeTo(own.distance, 1e-4));
    expect(core.normal.x, closeTo(-1.0, 1e-4));
    expect(core.point.x, closeTo(4.75, 1e-4));
  });

  test('down to the floor, and the floor ignored sees nothing', () {
    final (core, own) = both(Vector3(1.0, 3.0, 1.0), Vector3(0.0, -1.0, 0.0));
    expect(core.collider, same(floor));
    expect(core.distance, closeTo(own.distance, 1e-4));
    final (missed, _) = both(
      Vector3(1.0, 3.0, 1.0),
      Vector3(0.0, -1.0, 0.0),
      ignore: floor,
    );
    expect(missed.hit, isFalse);
  });

  test('a door moved this step is met where it is, and masked away', () {
    door.moveTo(Vector3(2.0, 1.0, 0.0));
    // Indexed for the walk; the core has not stepped since it moved.
    world.reindex();
    final (core, own) = both(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0));
    expect(own.collider, same(door));
    expect(core.collider, same(door), reason: 'placed before the ray');
    expect(core.distance, closeTo(own.distance, 1e-4));
    final (past, _) = both(
      Vector3(0.0, 1.0, 0.0),
      Vector3(1.0, 0.0, 0.0),
      mask: Layers.all & ~(1 << 2),
    );
    expect(past.collider, same(wall));
  });

  test('a ray that asks for triggers is the world\'s own', () {
    final hit = RayHit();
    world.raycast(
      Vector3(0.0, 1.0, 0.0),
      Vector3(-1.0, 0.0, 0.0),
      50.0,
      hit,
      includeTriggers: true,
    );
    expect(hit.collider, same(sensor));
    final solid = RayHit();
    world.raycast(Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0), 2.0, solid);
    expect(solid.hit, isFalse, reason: 'the core holds no trigger');
  });
}
