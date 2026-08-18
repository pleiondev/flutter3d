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
/// ## It no longer writes its own save
///
/// Actors are entities and what they are made of are components, so
/// `EcsWorld.save()` writes them — and refuses to write a component type
/// nobody registered. The `save`/`restore` pair that used to be here, walking
/// its own list and calling a hand-written method per actor, is gone. What
/// replaced it cannot forget the next component somebody adds.
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

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import '../ecs/ecs_world.dart';
import '../nav/navigation.dart';
import '../physics/layers.dart';
import 'actor.dart';
import 'actor_components.dart';
import 'brain.dart';
import 'health.dart';

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
    EcsWorld? entities,
    math.Random? random,
  })  : entities = entities ?? EcsWorld(),
        random = random ?? math.Random() {
    registerActorComponents(this.entities);
  }

  final CollisionWorld world;

  /// Where actors live. Shared with everything else that has moved across, so
  /// that one `save()` covers the lot.
  final EcsWorld entities;

  /// Randomness, shared so that a snapshot can carry where the dice were.
  final math.Random random;

  /// One handle per entity, because [Actor.onDamage] is on it.
  final Map<int, Actor> _handles = <int, Actor>{};

  /// Every actor, in the order they were spawned.
  ///
  /// Walks the handles rather than a component query, because an actor need not
  /// have any particular component: something that neither walks nor thinks is
  /// still something a collider can point back to.
  Iterable<Actor> get actors sync* {
    for (final actor in _handles.values) {
      if (actor.exists) yield actor;
    }
  }

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

  /// How fast the focus is moving, in metres per second.
  ///
  /// **Measured here rather than asked of a body**, because a focus is a point:
  /// callers pass one, and what it belongs to is optional. Measuring it is one
  /// subtraction a step for the whole system, and asking every brain to
  /// remember where the focus was last time would be one copy of that per
  /// brain.
  ///
  /// Zero for the step after a jump. A level load, a respawn or a lift moves
  /// the focus further in one step than anything can travel, and a velocity
  /// worked out from that is a number in the hundreds — which, to anything
  /// leading a shot, means firing at the horizon.
  Vector3 get focusVelocity => _focusVelocity;
  final Vector3 _focusVelocity = Vector3.zero();
  final Vector3 _lastFocus = Vector3.zero();
  bool _hasLastFocus = false;

  /// How far the focus may move in one step before it is treated as a jump
  /// rather than as movement.
  ///
  /// Two metres is a hundred and twenty metres a second at sixty hertz, which
  /// nothing in any of these games approaches — and a level load moves it much
  /// further than that.
  static const double _teleport = 2.0;

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

  /// Brings an actor into being: an entity, whichever components it needs, and
  /// the one handle that answers for it.
  ///
  /// **Every part is optional**, and each one left out is a component the
  /// entity does not carry:
  ///
  /// * no [body] — a turret, a trigger, a director that decides things and
  ///   stands nowhere;
  /// * no [health] — a lift, a lamp post, anything a rocket may ask and get
  ///   "nothing happened" from;
  /// * no [brain] — a barrel, or anything the game moves itself;
  /// * no [facing] — anything with no front.
  ///
  /// This used to require the first three. A game with a destructible crate had
  /// to give it a walking capsule and a brain that did nothing, which is the
  /// arrangement an entity-component design exists to remove.
  Actor spawn({
    CharacterController? body,
    Health? health,
    Brain? brain,
    Facing? facing,
  }) {
    final entity = entities.spawn();
    if (body != null) entities.set(entity, Body(body));
    if (health != null) entities.set(entity, Vitality(health));
    if (facing != null) entities.set(entity, facing);
    if (brain != null) entities.set(entity, Thinking(brain));

    final actor = Actor(entities, entity)
      ..onDamage = (double amount) => hurt(_handles[entity.index]!, amount);
    _handles[entity.index] = actor;
    body?.collider.userData = actor;
    return actor;
  }

  /// Takes an actor out of the world entirely.
  ///
  /// Not what death does — a corpse stays, because an emptied corridor should
  /// show what happened in it. This is for a game that removes things: an enemy
  /// that bursts, a summon whose time is up.
  void remove(Actor actor) {
    final body = actor.body;
    if (body != null) world.remove(body.collider);
    entities.despawn(actor.entity);
    _handles.remove(actor.entity.index);
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
    if (_hasLastFocus && dt > 0.0) {
      _focusVelocity
        ..setFrom(focus)
        ..sub(_lastFocus);
      if (_focusVelocity.length > _teleport) {
        _focusVelocity.setZero();
      } else {
        _focusVelocity.scale(1.0 / dt);
      }
    }
    _lastFocus.setFrom(focus);
    _hasLastFocus = true;

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

    for (final actor in actors.toList(growable: false)) {
      final body = actor.body;
      _mind.actor = actor;
      // Something with no body is somewhere the engine does not know; a brain
      // that wants a place gets it from a component of the game's own.
      _toFocus.setFrom(focus);
      if (body != null) _toFocus.sub(body.position);
      _distance = _toFocus.length;

      if (!actor.isAlive) {
        // A corpse still needs its body stepped, or it hangs in the air where
        // it died.
        body?.step(dt, wishDirection: Vector3.zero());
        continue;
      }

      final brain = actor.brain;
      if (brain != null) {
        // Thinking is throttled; moving is not. An actor whose movement ran
        // every fourth step would visibly stutter.
        final thinks = _distance < closeRange ||
            (_tick + actor.ordinal) % thinkInterval == 0;
        if (thinks) brain.think(_mind);
      }

      _wish.setZero();
      brain?.act(_mind);
      body?.step(dt, wishDirection: _wish);
    }
  }

  /// Applies damage from the outside — a shot, a blast, a crushing lift.
  ///
  /// Returns true if this killed it. What being hurt *looks* like is the
  /// brain's: this reports it and asks.
  bool hurt(Actor actor, double amount) {
    final health = actor.health;
    // Nothing to hurt is not a failure: a rocket asks everything in its radius
    // and a lamp post is entitled to say no.
    if (health == null || !health.isAlive) return false;

    _mind.actor = actor;
    final killed = health.damage(amount);
    if (killed) {
      // A corpse stops being an obstacle: walking into the bodies of everything
      // you have killed turns a corridor into a maze of your own making.
      actor.body?.collider.kind = ColliderKind.trigger;
      died.add(actor);
      actor.brain?.onDeath(_mind);
      return true;
    }

    hurtThisStep.add(ActorHurt(actor, amount));
    actor.brain?.onHurt(_mind, amount);
    return false;
  }

  /// Tells every actor within [radius] that something loud happened at [at].
  ///
  /// **The sense these actors did not have.** A brain that reacts only to being
  /// seen or being shot stands about while a fight happens next door, and a
  /// player who has just fired a shotgun knows they made a noise — a monster
  /// that did not notice reads as one that is switched off rather than one that
  /// is unaware.
  ///
  /// **Through walls on purpose.** Sound goes round corners and sight does not,
  /// which is the entire point: a line-of-sight test here would make this a
  /// slower copy of [canSee]. What a brain does about it is its own business,
  /// and the sensible thing is to go and look rather than to open fire.
  ///
  /// The dead are not told. Radius is in metres and is the caller's: a shotgun
  /// carries further than a footstep, and this layer has no opinion about
  /// either.
  void hear(Vector3 at, {required double radius}) {
    final squared = radius * radius;
    for (final actor in actors.toList(growable: false)) {
      if (!actor.isAlive) continue;
      final where = actor.position;
      if (where == null) continue;
      if (where.distanceToSquared(at) > squared) continue;
      _mind.actor = actor;
      actor.brain?.onNoise(_mind, at);
    }
  }

  /// Puts corpses back to being solid or not, after a snapshot has restored
  /// health it did not restore collider kinds for.
  ///
  /// Called by whoever applied the snapshot. A component cannot do it: the
  /// collider's kind is a fact about the collision world, and the health that
  /// decides it lives on a different component.
  void syncCorpses() {
    for (final actor in actors) {
      if (actor.health == null) continue;
      actor.body?.collider.kind =
          actor.isAlive ? ColliderKind.kinematic : ColliderKind.trigger;
    }
    died.clear();
    hurtThisStep.clear();
    damageToFocusThisStep = 0.0;
  }

  // MARK: - What a brain may do

  void steer(Actor actor, Vector3 direction) => _wish.setFrom(direction);

  /// Walk towards a point that is not the focus.
  ///
  /// Straight, and it slides off what it meets: the flow field is baked towards
  /// the focus and cannot route anywhere else, which is why this is a separate
  /// method rather than `steerTowardsFocus(point)`. A patrol between two posts
  /// wants exactly this; an enemy that must cross a level to somewhere the
  /// player is not wants navigation, and that is a bigger change than this one.
  void steerTowards(Actor actor, Vector3 point) {
    final body = actor.body;
    if (body == null) return;
    _wish
      ..setFrom(point)
      ..sub(body.position)
      ..y = 0.0;
    final length = _wish.length;
    if (length > 1e-6) _wish.scale(1.0 / length);
  }

  /// Asks this actor's body to jump.
  ///
  /// Through the controller's own buffered request rather than by writing
  /// `velocity.y`, and the difference is the whole reason it is here: a brain
  /// setting the speed directly can do it in mid-air, every step, and the actor
  /// flies. `requestJump` is refused unless the body is on the ground or inside
  /// its coyote window, which is the same rule the player plays by.
  void jump(Actor actor) => actor.body?.requestJump();

  /// A route when the level has one, and straight at the focus when it does
  /// not — which the field itself reports for the last cell, where straight is
  /// the right answer anyway.
  void steerTowardsFocus(Actor actor) {
    final body = actor.body;
    final routed = body != null &&
        (navigation?.steer(
              body.position,
              _wish,
              radius: body.halfExtents.x,
              height: body.halfExtents.y * 2.0,
            ) ??
            false);
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
    if (actor.facing == null) return;
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
    final body = actor.body;
    // Nothing to see from. False rather than true: a brain that asks and gets
    // an unconditional yes charges at a player through a wall.
    if (body == null || !actor.eyeLevel(_eye)) return false;
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
      ignore: body.collider,
    );
  }
}
