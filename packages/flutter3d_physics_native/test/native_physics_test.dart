/// One backend for a whole run: the core where it loads, the Dart reference
/// where it does not or where the build asked for it.
///
///     flutter test test/native_physics_test.dart
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  tearDown(() => PhysicsBackend.current = const DartPhysics());

  test(
    'by default the run is on the core, and a world made is on it',
    () async {
      final start = await startPhysics();
      expect(start.fallbackBecause, isNull);
      expect(PhysicsBackend.current.name, 'native');
      final world = CollisionWorld();
      expect(PhysicsBackend.current.dynamics(world), isA<NativeDynamics>());
      // Its characters and rays as well as its bodies.
      expect(world.characterMover, isA<NativeCharacterMover>());
      expect(world.rays, isA<NativeWorldRays>());
    },
  );

  test('asked for the reference, the run is on Dart', () async {
    final start = await startPhysics(asked: 'dart');
    expect(start.backend, isA<DartPhysics>());
    final world = CollisionWorld();
    expect(PhysicsBackend.current.dynamics(world), isA<Dynamics>());
    expect(world.characterMover, isNull);
  });

  test('a core that will not start is a fallback, with the reason', () async {
    // Mutation: letting the first world's error out of startPhysics.
    final start = await startPhysics(
      probe: () => throw StateError('the core is ABI 1 and these are 2'),
    );
    expect(start.backend, isA<DartPhysics>());
    expect(PhysicsBackend.current, isA<DartPhysics>());
    expect(start.fallbackBecause, contains('ABI 1'));
  });

  test('a world attached casts its rays on the core, and released, on its '
      'own again', () async {
    await startPhysics();
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(10.0, 1.0, 10.0));
    PhysicsBackend.current.attach(world);
    expect(world.rays, isA<NativeWorldRays>());
    world.update();
    final hit = RayHit();
    expect(
      world.raycast(Vector3(0.0, 3.0, 0.0), Vector3(0.0, -1.0, 0.0), 10.0, hit),
      isTrue,
    );
    expect(hit.distance, closeTo(3.0, 1e-4));
    PhysicsBackend.current.release(world);
    expect(world.rays, isNull);
    expect(world.characterMover, isNull);
    expect(world.mirrors, isEmpty);
  });

  test('chosen once, the backend stays for the run', () async {
    await startPhysics(asked: 'dart');
    // Mutation: choosing afresh on every ask, which would put a run's later
    // worlds on the core under the earlier ones on Dart.
    expect(usePhysics(asked: 'native'), isA<DartPhysics>());
    await startPhysics();
    expect(usePhysics(asked: 'dart'), isA<NativePhysics>());
    expect(physicsFallbackReason, isNull);
  });

  test(
    'dynamics made for an attached world take it over: one core world',
    () async {
      await startPhysics();
      final world = CollisionWorld();
      PhysicsBackend.current.attach(world);
      final dynamics = PhysicsBackend.current.dynamics(world) as NativeDynamics;
      // Mutation: leaving the attached one in place, whose mirror would be
      // brought up to date every step for nobody.
      expect(world.mirrors, <Object>[dynamics]);
      expect(
        (world.characterMover! as NativeCharacterMover).dynamics,
        dynamics,
      );
    },
  );
}
