import 'package:vector_math/vector_math.dart';

import 'actor.dart';

/// Where an actor's own animation walks it — the seam root motion comes
/// into the simulation through.
///
/// The simulation does not know what an animation is: a game that steps
/// one for each actor answers here with how far its stride carried the
/// body this step, along the floor in the world, and `ActorSystem` sweeps
/// the body that far in place of accelerating it towards the brain's wish.
abstract interface class ActorStrides {
  /// [actor]'s travel along the floor for this step of [dt], or null for a
  /// body moved by its brain's wish. Called once a step for every actor,
  /// after its brain has acted, dead or alive.
  Vector3? strideOf(Actor actor, double dt);
}
