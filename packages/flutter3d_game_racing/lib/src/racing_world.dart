/// The world a race is run in.
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionWorld;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;
import 'package:vector_math/vector_math.dart';

/// How fast a racing game's world falls, m/s²: twice the Earth's, near
/// enough.
///
/// **Deliberately above the real figure**, and the game's, not a car's: an
/// arcade car jumps, and a jump under real gravity hangs long enough to feel
/// like a bug. Everything in the race reads it from the world — the cars'
/// fall and the grip their tyres have (a "1.05 g" tyre holds 1.05 × this),
/// the spray thrown off a wet wheel, the cones knocked over — so it is one
/// number, the world's, rather than the car's 20 beside a spray's 9.81.
/// Before 1.0 it was `VehicleSettings.gravity`.
const double racingGravity = 20.0;

/// The world a race is run in: [racingGravity] down, otherwise the standard
/// world. What [raceIn] gives a world, and what a test that drives a car on
/// its own makes its `CollisionWorld` with.
final WorldProperties racingWorld = WorldProperties(
  gravity: Vector3(0.0, -racingGravity, 0.0),
);

/// Makes [world] a race's: [racingWorld], with what [level] says of its
/// world laid over it (`Level.worldOver`) — a circuit set on the Moon is the
/// Moon for every car on it. Throws an `UnknownMaterialException` for a
/// level filled with a material [world]'s catalogue does not have.
void raceIn(CollisionWorld world, {Level? level}) {
  world.properties =
      level?.worldOver(racingWorld, materials: world.materials) ?? racingWorld;
}
