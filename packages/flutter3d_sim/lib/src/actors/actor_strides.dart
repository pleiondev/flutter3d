import 'package:vector_math/vector_math.dart';

import 'actor.dart';

/// Where an actor's own animation walks it — the seam root motion comes
/// into the simulation through.
///
/// The simulation does not know what an animation is: a game that steps
/// one for each actor answers here with how far its stride carried the
/// body this step, along the floor in the world, and `ActorSystem` sweeps
/// the body that far in place of accelerating it towards the brain's wish.
///
/// **Saved with the actors.** What steps the animations is simulation
/// state: `ActorSystem.save` writes [save] beside its own and `restore`
/// hands it back with the actors as they now are, so a rewind or a replay
/// steps on to the same strides. Nothing to save by default.
abstract class ActorStrides {
  /// [actor]'s travel along the floor for this step of [dt], or null for a
  /// body moved by its brain's [wish]. Called once a step for every actor,
  /// body or none, after its brain has acted, dead or alive.
  ///
  /// [wish] is where the brain asked to go — the answer to "how fast does it
  /// mean to move", which a body driven by its own stride cannot give: its
  /// velocity is last step's stride, and a graph asked to walk by that would
  /// never leave its idle.
  Vector3? strideOf(Actor actor, Vector3 wish, double dt);

  /// Whatever stepping changes, as plain JSON; null for nothing.
  Object? save() => null;

  /// Back to what [save] wrote, for [actors] as the restore left them.
  void restore(Object? from, Iterable<Actor> actors) {}

  /// [actor] is to make the gesture called [name] — a one-off the game's
  /// animation plays once and leaves, asked for on this step by whoever is
  /// directing it. Nothing by default, which is right for strides that are
  /// not an animation.
  void gesture(Actor actor, String name) {}
}
