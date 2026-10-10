/// The shooter staged on the run's physics: dynamics of its own on a
/// backend with characters of its own, none on the reference.
library;

import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_demo_content/shooter_staging.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

Level _room() => Level.fromJson(<String, Object?>{
  'version': 1,
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.5, 0.5, 0.5, 1],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0, -0.5, 0],
      'size': <double>[20, 1, 20],
      'material': 'stone',
    },
  ],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0, 3, 0],
      'intensity': 4,
      'range': 20,
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'player_spawn',
      'at': <double>[0, 0, 5],
    },
    <String, Object?>{
      'type': 'exit',
      'at': <double>[0, 0, -5],
    },
  ],
});

/// A backend with characters of its own, which only counts what it makes.
final class _Counting extends PhysicsBackend {
  final List<CollisionWorld> made = <CollisionWorld>[];
  @override
  String get name => 'counting';
  @override
  RigidDynamics dynamics(CollisionWorld world, {Vector3? gravity}) {
    made.add(world);
    return const DartPhysics().dynamics(world, gravity: gravity);
  }
}

Staged _staged(CollisionWorld world) {
  final level = _room()..addTo(world);
  return stage(
    level,
    world,
    input: InputState(),
    registry: sampleRegistry(),
    inventory: startingInventory(),
  );
}

void main() {
  test('on a backend of its own, the world is given its dynamics', () {
    final backend = _Counting();
    final world = CollisionWorld(backend: backend);
    _staged(world);
    // Mutation: staging with none unless a caller hands some over, which
    // leaves a headless run and a server's replay on other physics than the
    // game that recorded the run.
    expect(backend.made, <CollisionWorld>[world]);
  });

  test('on the reference, none: the crypt as it always was', () {
    expect(shooterDynamics(CollisionWorld()), isNull);
  });
}
