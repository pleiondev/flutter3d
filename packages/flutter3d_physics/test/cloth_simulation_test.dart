/// Cloth from the run's backend: the reference's own is `stepCloth` on the
/// mesh and nothing else, and a backend with a cloth of its own is asked
/// for it.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A backend with a cloth of its own, which only counts the meshes it was
/// given.
final class _Counting implements PhysicsBackend, ClothPhysics {
  final List<ClothMesh> given = <ClothMesh>[];

  @override
  String get name => 'counting';

  @override
  ClothSimulation cloth(ClothMesh mesh) {
    given.add(mesh);
    return DartCloth(mesh);
  }

  @override
  RigidDynamics dynamics(CollisionWorld world, {Vector3? gravity}) =>
      const DartPhysics().dynamics(world, gravity: gravity);

  @override
  void attach(CollisionWorld world) {}

  @override
  void release(CollisionWorld world) {}
}

void main() {
  test('the reference steps the mesh exactly as stepCloth does', () {
    ClothMesh sheet() => ClothMesh.grid(cols: 8, rows: 8, height: 1.0);
    final ball = <ClothObstacle>[
      ClothObstacle(CollisionSphere(0.2), Vector3(0.35, 0.6, 0.35)),
    ];
    const settings = ClothSettings(wind: WindSettings(velocityZ: 2.0));
    final stepped = sheet();
    final cloth = const DartPhysics().cloth(sheet());
    expect(cloth, isA<DartCloth>());
    for (var i = 0; i < 20; i++) {
      stepCloth(stepped, settings, 1 / 60, obstacles: ball);
      cloth.step(settings, 1 / 60, obstacles: ball);
    }
    expect(cloth.mesh.positions, stepped.positions);
    expect(cloth.mesh.velocities, stepped.velocities);
    cloth.dispose();
  });

  test('a backend with a cloth of its own is asked for it', () {
    final backend = _Counting();
    final mesh = ClothMesh.grid(cols: 4, rows: 4);
    backend.cloth(mesh);
    // Through the extension too, as code that holds only a PhysicsBackend
    // asks. Mutation: the extension always answering the reference.
    final PhysicsBackend current = backend;
    current.cloth(mesh);
    expect(backend.given, <ClothMesh>[mesh, mesh]);
  });
}
