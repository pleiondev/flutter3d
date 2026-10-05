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

/// The dynamics the run's backend gives [world] — see `usePhysics` — or
/// none on the Dart reference: the crypt has no loose bodies, so the core
/// is here to walk the player and the monsters through the level it
/// mirrors, and the reference walks them with their own sweeps.
RigidDynamics? dungeonDynamics(CollisionWorld world) => switch (usePhysics()) {
  final NativePhysics core => core.dynamics(world),
  _ => null,
};
