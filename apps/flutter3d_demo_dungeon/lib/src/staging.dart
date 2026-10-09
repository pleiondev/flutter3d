/// The dungeon's own assembly of a level into a run.
///
/// **It lives in `package:flutter3d_demo_content/shooter_staging.dart` now**, so a
/// package can reach it — the agent's sim server kept a copy of its own while
/// it could not. Exported here so everything in this application that already
/// imports this file keeps doing so.
library;

import 'package:flutter3d_demo_content/shooter_staging.dart'
    show shooterDynamics;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';

export 'package:flutter3d_demo_content/shooter_staging.dart'
    show Staged, shooterDynamics, stage, startingInventory;

/// The dynamics the run's backend gives [world]: the shooter's own
/// [shooterDynamics], once the run's backend is chosen — see `usePhysics`.
RigidDynamics? dungeonDynamics(CollisionWorld world) {
  usePhysics();
  return shooterDynamics(world);
}
