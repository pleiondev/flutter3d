/// The dungeon's own assembly of a level into a run.
///
/// **It lives in `package:flutter3d_game_shooter/staging.dart` now**, so a
/// package can reach it — the agent's sim server kept a copy of its own while
/// it could not. Exported here so everything in this application that already
/// imports this file keeps doing so.
library;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

export 'package:flutter3d_game_shooter/staging.dart'
    show Staged, stage, startingInventory;

/// What moves the crypt's characters: the physics core, unless the build is
/// made with `--dart-define=FLUTTER3D_PHYSICS=dart`, which leaves them to
/// their own sweeps in plain Dart — the reference.
const String physicsBackend = String.fromEnvironment(
  'FLUTTER3D_PHYSICS',
  defaultValue: 'native',
);

/// The dynamics [physicsBackend] names for [world], or none: the crypt has
/// no loose bodies, so the core is here to walk the player and the monsters
/// through the level it mirrors. Load it first, with `loadPhysicsCore`.
RigidDynamics? dungeonDynamics(CollisionWorld world) => physicsBackend == 'dart'
    ? null
    : NativeDynamics(world: world, movesCharacters: true, castsRays: true);
