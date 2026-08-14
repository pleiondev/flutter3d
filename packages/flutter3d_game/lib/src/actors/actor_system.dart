/// Everything in the world that walks and can be hurt, and the machinery all of
/// it shares whatever game it is in.
///
/// ## What it does, and what it refuses to
///
/// It steps bodies, throttles thinking, turns actors towards things, steers
/// them round corners, tests lines of sight, applies damage, counts deaths and
/// stops corpses blocking corridors. **It has no idea what any of them is
/// doing.** That is [Brain], and the shooter's chase-and-attack machine — with
/// its alert pause, its flinch roll and its weapon — is in `lib/shooter.dart`,
/// which the barrel does not export.
///
/// The distinction is not decoration. This file was `MonsterSystem`, and the
/// engine therefore knew what a monster was; a platformer has none, and the
/// first thing that would have happened when one was written is that half of
/// this file would have been unusable and the other half copied.
///
/// ## Nothing targets anything but the focus
///
/// One thing that everything pays attention to, which the caller names each
/// step. No infighting, and it is a deliberate trade rather than an omission:
/// it keeps the target a single reference rather than a search, and removes the
/// whole class of bug where two actors lock onto each other and the fight
/// resolves itself off screen. It is also what makes one flow field enough for
/// the entire level.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import '../nav/navigation.dart';
import '../physics/layers.dart';
import 'actor.dart';
import 'brain.dart';

/// An actor that took damage this step and survived it.
final class ActorHurt {
  ActorHurt(this.actor, this.amount);
  final Actor actor;
  final double amount;

  /// Whether it visibly reacted. Set by whatever decided that it did — a
  /// caller can tell a grunt from a scream.
  bool staggered = false;
}

final class ActorSystem {
  ActorSystem({
    required this.world,
    math.Random? random,
  }) : random = random ?? math.Random();

  final CollisionWorld world;

  /// Randomness, shared so that a snapshot can carry where the dice were.
  final math.Random random;

  final List<Actor> actors = <Actor>[];

  /// How to get to the focus from anywhere, or null for "walk straight at it".
  Navigation? navigation;

  /// How often an actor far from the focus thinks.
  ///
  /// Sight tests are raycasts and they are the expensive part. Something
  /// twenty-five metres away deciding four times a second instead of sixty is
  /// invisible, and without this thirty actors are thirty rays every step.
  int thinkInterval = 4;

  /// Beyond this, an actor is on the slow schedule.
  double closeRange = 18.0;

  /// Actors that died this step.
  final List<Actor> died = <Actor>[];

  /// Actors that took damage this step and survived.
  final List<ActorHurt> hurtThisStep = <ActorHurt>[];

  /// Damage dealt to whatever everything is paying attention to, this step.
  double damageToFocusThisStep = 0.0;

  /// Where the focus is, and what body it belongs to. Set by [step].
  Vector3 get focus => _focus;
  final Vector3 _focus = Vector3.zero();
  Collider? focusBody;

  /// From the actor currently being thought about to the focus.
  Vector3 get toFocus => _toFocus;
  double get distanceToFocus => _distance;

  int _tick = 0;
  double _distance = 0.0;

  final Vector3 _toFocus = Vector3.zero();
  final Vector3 _wish = Vector3.zero();
  final Vector3 _eye = Vector3.zero();
  final Vector3 _aim = Vector3.zero();
  final RayHit _sight = RayHit();
  late final Mind _mind = Mind(this);

  /// Adds an actor and wires it to this system.
  Actor add(Actor actor) {
    actor
      ..ordinal = actors.length
      ..onDamage = (double amount) => hurt(actor, amount);
    actors.add(actor);
    return actor;
  }

  int get aliveCount {
    var count = 0;
    for (final actor in actors) {
      if (actor.isAlive) count++;
    }
    return count;
  }

  /// Advances every actor.
  void step(
    double dt, {
    required Vector3 focus,
    Collider? focusBody,
  }) {
    _tick++;
    _focus.setFrom(focus);
    this.focusBody = focusBody;
    damageToFocusThisStep = 0.0;
    died.clear();
    hurtThisStep.clear();

    // Once for the whole system, not once per actor: everything is walking to
    // the same place, which is the entire reason this is a field and not one
    // search per actor.
    navigation?.update(focus);

    _mind.dt = dt;

    for (final actor in actors) {
      _mind.actor = actor;
      _toFocus
        ..setFrom(focus)
        ..sub(actor.position);
      _distance = _toFocus.length;

      if (!actor.isAlive) {
        // A corpse still needs its body stepped, or it hangs in the air where
        // it died.
        actor.body.step(dt, wishDirection: Vector3.zero());
        continue;
      }

      // Thinking is throttled; moving is not. An actor whose movement ran every
      // fourth step would visibly stutter.
      final thinks = _distance < closeRange ||
          (_tick + actor.ordinal) % thinkInterval == 0;
      if (thinks) actor.brain.think(_mind);

      _wish.setZero();
      actor.brain.act(_mind);
      actor.body.step(dt, wishDirection: _wish);
    }
  }

  /// Applies damage from the outside — a shot, a blast, a crushing lift.
  ///
  /// Returns true if this killed it. What being hurt *looks* like is the
  /// brain's: this reports it and asks.
  bool hurt(Actor actor, double amount) {
    if (!actor.isAlive) return false;

    _mind.actor = actor;
    final killed = actor.health.damage(amount);
    if (killed) {
      // A corpse stops being an obstacle: walking into the bodies of everything
      // you have killed turns a corridor into a maze of your own making.
      actor.body.collider.kind = ColliderKind.trigger;
      died.add(actor);
      actor.brain.onDeath(_mind);
      return true;
    }

    hurtThisStep.add(ActorHurt(actor, amount));
    actor.brain.onHurt(_mind, amount);
    return false;
  }

  // MARK: - What a brain may do

  void steer(Actor actor, Vector3 direction) => _wish.setFrom(direction);

  /// A route when the level has one, and straight at the focus when it does
  /// not — which the field itself reports for the last cell, where straight is
  /// the right answer anyway.
  void steerTowardsFocus(Actor actor) {
    final routed = navigation?.steer(
          actor.position,
          _wish,
          radius: actor.body.halfExtents.x,
          height: actor.body.halfExtents.y * 2.0,
        ) ??
        false;
    if (routed) return;
    // Straight at it, horizontally. The controller does the sliding, which is
    // what keeps a corner from being a wall.
    _wish.setValues(_toFocus.x, 0.0, _toFocus.z);
    if (_wish.length2 > 1e-6) _wish.normalize();
  }

  /// What [steerTowardsFocus] or [steer] last asked for, so a brain can turn to
  /// face where it is going rather than where the focus is. Around a corner
  /// those are different directions, and an actor sliding sideways while
  /// staring through a wall is the tell that gives a flow field away.
  Vector3 get heading => _wish;

  void turnTowards(Actor actor, double x, double z, double dt) {
    if (x == 0.0 && z == 0.0) return;
    final wanted = math.atan2(-x, -z);
    final delta = _shortestAngle(actor.yaw, wanted);
    final step = actor.turnRate * dt;
    actor.yaw += delta.abs() <= step ? delta : (delta.isNegative ? -step : step);
  }

  static double _shortestAngle(double from, double to) {
    const twoPi = 2.0 * math.pi;
    var delta = (to - from) % twoPi;
    if (delta > math.pi) {
      delta -= twoPi;
    } else if (delta < -math.pi) {
      delta += twoPi;
    }
    return delta;
  }

  /// Whether an actor has a clear line to the focus.
  ///
  /// Against the level only. A ray that stopped on another actor would mean a
  /// crowd blinds itself, and two of them standing in a doorway would each wait
  /// for the other to move.
  bool canSee(Actor actor) {
    actor.eyeLevel(_eye);
    _aim
      ..setFrom(_focus)
      ..sub(_eye);
    final distance = _aim.length;
    if (distance < 1e-4) return true;
    _aim.scale(1.0 / distance);

    return !world.raycast(
      _eye,
      _aim,
      distance,
      _sight,
      mask: CollisionLayers.world,
      ignore: actor.body.collider,
    );
  }

  /// Everything, in the order it was added.
  ///
  /// **Positional, not named**, which is the boundary the whole snapshot
  /// mechanism draws: it restores a world that already exists, so the *n*th
  /// actor is the *n*th actor and nothing has to invent an identity scheme.
  List<Map<String, Object?>> save() =>
      <Map<String, Object?>>[for (final actor in actors) actor.save()];

  void restore(Object? from) {
    if (from is! List) return;
    for (var i = 0; i < actors.length && i < from.length; i++) {
      final row = from[i];
      if (row is Map) actors[i].restore(row.cast<String, Object?>());
    }
    died.clear();
    hurtThisStep.clear();
    damageToFocusThisStep = 0.0;
  }
}
