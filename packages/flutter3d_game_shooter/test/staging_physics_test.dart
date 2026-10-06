/// The shooter staged on the run's physics: dynamics of its own on a
/// backend with characters of its own, none on the reference.
library;

import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_game_shooter/staging.dart';
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
final class _Counting implements PhysicsBackend {
  final List<CollisionWorld> made = <CollisionWorld>[];
  @override
  String get name => 'counting';
  @override
  RigidDynamics dynamics(CollisionWorld world, {Vector3? gravity}) {
    made.add(world);
    return const DartPhysics().dynamics(world, gravity: gravity);
  }

  @override
  void attach(CollisionWorld world) {}
  @override
  void release(CollisionWorld world) {}
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
  final was = PhysicsBackend.current;
  tearDown(() => PhysicsBackend.current = was);

  test('on a backend of its own, the world is given its dynamics', () {
    final backend = _Counting();
    PhysicsBackend.current = backend;
    final world = CollisionWorld();
    _staged(world);
    // Mutation: staging with none unless a caller hands some over, which
    // leaves a headless run and a server's replay on other physics than the
    // game that recorded the run.
    expect(backend.made, <CollisionWorld>[world]);
  });

  test('on the reference, none: the crypt as it always was', () {
    PhysicsBackend.current = const DartPhysics();
    expect(shooterDynamics(CollisionWorld()), isNull);
  });
}
