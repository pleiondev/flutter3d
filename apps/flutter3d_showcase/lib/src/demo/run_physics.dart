import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show usePhysics;

/// [world], on the run's physics: its character moves, rays and sweeps on
/// the core, or its own on the Dart reference — as every game's are. A
/// page that makes a world asks for this, so what it shows is what a game
/// built from it would do.
CollisionWorld onRunPhysics(CollisionWorld world) {
  usePhysics().attach(world);
  return world;
}
