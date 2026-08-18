/// What decides where an actor is going.
///
/// ## Why this is a class and not an enum
///
/// It was an enum — `idle`, `alert`, `chase`, `attack`, `hurt`, `dead` — with
/// two switches over it in the engine, and the engine therefore knew what a
/// monster was. A platformer has no monsters. It has an enemy that walks a
/// ledge and turns round at the edge, a bird on a fixed path, a block that
/// drops when you stand under it; none of those has an `alert` state and none
/// of them is a shooter's chase.
///
/// This package's own `gift.dart` already wrote the rule down:
///
/// > A hierarchy rather than an enum with a switch, for the same reason
/// > `EntityKind` is one: every job that treats gifts differently would
/// > otherwise grow its own switch over the same eight names in a different
/// > file, and the switches drift.
///
/// So the engine ships bodies that walk, health that can run out, turning,
/// steering and a line-of-sight test; and the game ships the thing that
/// decides. The shooter's chase-and-attack machine is in `lib/shooter.dart`,
/// which is not exported from the barrel, so a game that is not a shooter
/// never sees it.
///
/// ## `base`, not `interface`
///
/// A game writes `extends Brain`, which is how `Mechanism` works in this
/// package too. It means the four hooks below can have defaults, and a brain
/// that only cares about walking overrides one method.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'actor.dart';
import 'actor_system.dart';

abstract base class Brain {
  /// Decides. Called on the steps the system chooses to think on — see
  /// [ActorSystem.thinkInterval], which is why deciding may be expensive and
  /// moving may not.
  void think(Mind it) {}

  /// Moves. Called every step, for every actor, before its body is stepped.
  void act(Mind it) {}

  /// Something hurt this actor and it lived.
  void onHurt(Mind it, double amount) {}

  /// Something hurt this actor and it did not.
  void onDeath(Mind it) {}

  /// Whatever has to survive a save. Empty for a brain with no memory.
  Map<String, Object?> save() => const <String, Object?>{};

  void restore(Map<String, Object?> from) {}
}

/// Everything a brain is allowed to know, and the few things it may do.
///
/// Handed in rather than reached for: a brain holding a reference to the
/// collision world could sweep, raycast and spawn, and then every brain anybody
/// writes is entitled to the whole engine. This is the surface a decision
/// actually needs.
final class Mind {
  Mind(this.system);

  final ActorSystem system;

  /// Whose decision this is.
  late Actor actor;

  /// Seconds this step.
  late double dt;

  /// What every actor in the world is currently paying attention to.
  ///
  /// The player, in every game so far, and named for what it is rather than
  /// for who it usually is: a game where the monsters chase a runaway cart
  /// points this at the cart and nothing here changes.
  Vector3 get focus => system.focus;

  /// The body at [focus], when there is one. For ignoring it in a raycast, and
  /// for telling whether a shot hit it.
  Collider? get focusBody => system.focusBody;

  /// From the actor to the focus. Live, and not to be kept.
  Vector3 get toFocus => system.toFocus;

  /// How far away the focus is.
  double get distance => system.distanceToFocus;

  /// Randomness that a snapshot can carry. See `GameRandom`.
  math.Random get random => system.random;

  /// Whether there is a clear line from this actor's eye to the focus.
  ///
  /// Against the level only. A ray that stopped on another actor would mean a
  /// crowd blinds itself, and two of them standing in a doorway would each wait
  /// for the other to move.
  bool canSee() => system.canSee(actor);

  /// Walk this way, on the ground. Length is speed: a half-length vector is a
  /// request to walk at half pace.
  void steer(Vector3 direction) => system.steer(actor, direction);

  /// Walk towards the focus, round corners if the level has a navigation grid
  /// and straight at it if it has not.
  ///
  /// The one piece of pathfinding a brain gets for free, because every brain
  /// that chases anything wants exactly this and none of them should have to
  /// know what a flow field is.
  void steerTowardsFocus() => system.steerTowardsFocus(actor);

  /// Walk towards a point that is not the focus. Straight, sliding off walls.
  ///
  /// [steerTowardsFocus] is kept separate rather than being this with the focus
  /// passed in, and the difference matters: that one follows the level's flow
  /// field round corners and this one cannot, because the field is baked
  /// towards the focus. A patrol wants this; a chase wants the other.
  void steerTowards(Vector3 point) => system.steerTowards(actor, point);

  /// Ask to jump. Refused in mid-air, as it is for the player.
  void jump() => system.jump(actor);

  /// Turn to face a direction on the ground, at the actor's turn rate.
  void turnTowards(double x, double z) => system.turnTowards(actor, x, z, dt);

  /// Stop.
  void halt() => system.steer(actor, Vector3.zero());
}
