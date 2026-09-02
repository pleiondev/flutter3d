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
/// ## It no longer writes the actors' save, only its own
///
/// Actors are entities and what they are made of are components, so
/// `EcsWorld.save()` writes them — and refuses to write a component type
/// nobody registered. The `save`/`restore` pair that used to be here, walking
/// its own list and calling a hand-written method per actor, is gone. What
/// replaced it cannot forget the next component somebody adds.
///
/// What came back is much smaller and is about the *system*: the think
/// schedule and where the focus was last step belong to no entity, so nothing
/// was carrying them and every restore silently re-phased the thinking and
/// forgot the aim. See [save].
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
import '../math/motion.dart';
import '../math/tolerances.dart';
import '../nav/jump_links.dart';
import '../nav/navigation.dart';
import '../physics/layers.dart';
import '../save/game_random.dart';
import 'actor.dart';
import 'actor_components.dart';
import 'actor_hurt.dart';
import 'brain.dart';
import 'health.dart';

export 'actor_hurt.dart';

final class ActorSystem {
  ActorSystem({required this.world, required this.random, EcsWorld? entities})
    : entities = entities ?? EcsWorld() {
    registerActorComponents(this.entities);
  }

  final CollisionWorld world;

  /// Where actors live. Shared with everything else that has moved across, so
  /// that one `save()` covers the lot.
  final EcsWorld entities;

  /// Randomness, shared so that a snapshot can carry where the dice were.
  ///
  /// **[GameRandom] and not `math.Random`, and the line above used to be a
  /// lie.** `math.Random` has no readable state, so a snapshot cannot carry
  /// where its dice were — which `GameRandom`'s own doc says in its first
  /// paragraph, four files away. The two sat side by side in this package for
  /// as long as nobody read them together.
  ///
  /// **Required and not defaulted**, which is the other half. It defaulted to
  /// an unseeded `math.Random()`, and the shipped shooter took that default:
  /// its saves restored everything except the flinch rolls, and ARCHITECTURE.md §9.3 —
  /// no randomness except through a `Random` that was handed in — was being
  /// kept by nothing at all. A default is how a caller takes a decision without
  /// making one.
  final GameRandom random;

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
      ..onDamage = (double amount, Object? from) =>
          hurt(_handles[entity.index]!, amount, from: from);
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

  /// Forgets what happened last step: the dead, the hurt, and what the focus
  /// took.
  ///
  /// **Called by the game at the top of its own step, not by [step], and that
  /// is a bug fix rather than a preference.** These lists used to be cleared
  /// here at the start of `step`, which is halfway through a game's step — and
  /// in the shooter the player's own shot is fired *before* the actors think.
  /// So a monster killed by the player was added to [died] and wiped again in
  /// the same step, before anything downstream could look: no death sound for
  /// anything the player killed, no sparks, and nothing to count. The monster
  /// was dead and the news never left the building.
  ///
  /// Whoever owns the step owns the clearing, which is the rule every other
  /// per-step flag in this repository keeps — `InputState.beginStep`,
  /// `RaceState.clearStepFlags`, and the genre simulations' own.
  void beginStep() {
    damageToFocusThisStep = 0.0;
    died.clear();
    hurtThisStep.clear();
    _begun = true;
  }

  /// Whether [beginStep] has been called since the last [step].
  ///
  /// Only for the assertion below. A caller who forgets does not crash — the
  /// lists simply grow and the damage counter keeps climbing, which is a slow
  /// leak and a wrong number rather than a failure, and exactly the kind of
  /// thing that is found six months later.
  bool _begun = false;

  /// Advances every actor.
  void step(double dt, {required Vector3 focus, Collider? focusBody}) {
    // **Thrown, not asserted, and the difference is the whole point.** This is
    // a protocol between two objects, not an invariant of one: a game that
    // calls `step` without `beginStep` is a game whose dead and hurt lists grow
    // for ever and whose damage counter keeps climbing — a slow leak and a
    // wrong number rather than a crash, found six months later. An `assert`
    // says that out loud in debug and says nothing at all in the build a player
    // runs, which is the build where six months happen.
    if (!_begun) {
      throw StateError(
        'call ActorSystem.beginStep() at the top of your own step. It forgets '
        "last step's dead and hurt; step() no longer does, because it runs "
        "halfway through a game's step and was wiping deaths the game had not "
        'read yet.',
      );
    }
    _begun = false;
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
        final thinks =
            _distance < closeRange ||
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
  bool hurt(Actor actor, double amount, {Object? from}) {
    final health = actor.health;
    // Nothing to hurt is not a failure: a rocket asks everything in its radius
    // and a lamp post is entitled to say no.
    if (health == null || !health.isAlive) return false;

    _mind.actor = actor;
    _mind.hurtBy = from;
    final killed = health.damage(amount);
    if (killed) {
      // A corpse stops being an obstacle: walking into the bodies of everything
      // you have killed turns a corridor into a maze of your own making.
      actor.body?.collider.kind = ColliderKind.trigger;
      died.add(actor);
      actor.brain?.onDeath(_mind);
      return true;
    }

    hurtThisStep.add(ActorHurt(actor, amount, from: from));
    actor.brain?.onHurt(_mind, amount);
    _mind.hurtBy = null;
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
      actor.body?.collider.kind = actor.isAlive
          ? ColliderKind.kinematic
          : ColliderKind.trigger;
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
    if (length > Tolerance.zeroLength) _wish.scale(1.0 / length);
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
    final routes = navigation;
    if (body != null && routes != null) {
      // The body's own reach, read off its tuning: a grid baked with jump
      // links hands this body the ones it takes, and a grid baked without
      // makes the reach a number nobody reads.
      final reach = routes.grid.jumpLinks.isEmpty
          ? null
          : JumpReach.of(body.tuning);
      final routed = routes.steer(
        body.position,
        _wish,
        radius: body.halfExtents.x,
        height: body.halfExtents.y * 2.0,
        jump: reach,
      );
      if (routed) {
        if (reach != null) _takeOffIfDue(body, routes, reach);
        return;
      }
    }
    // Straight at it, horizontally. The controller does the sliding, which is
    // what keeps a corner from being a wall.
    _wish.setValues(_toFocus.x, 0.0, _toFocus.z);
    if (_wish.length2 > Tolerance.zeroLength) _wish.normalize();
  }

  /// Jumps when the field's next step from where [body] stands is a link and
  /// the body is at the take-off.
  ///
  /// At the take-off means within the cell's own radius of its centre: a
  /// link is baked from cell centre to cell centre, and a body that leaves
  /// from the near side of a half-metre cell lands a quarter metre short of
  /// where the reach was measured. The request goes through the controller's
  /// buffered jump like the player's, so asking every step until the body is
  /// airborne asks exactly once.
  void _takeOffIfDue(
    CharacterController body,
    Navigation routes,
    JumpReach reach,
  ) {
    if (!body.isGrounded) return;
    final link = routes.jumpAhead(
      body.position,
      radius: body.halfExtents.x,
      height: body.halfExtents.y * 2.0,
      jump: reach,
    );
    if (link == null) return;
    routes.grid.centreOf(link.from, _takeOff);
    final dx = _takeOff.x - body.position.x;
    final dz = _takeOff.z - body.position.z;
    final within = routes.grid.cellSize * 0.5;
    if (dx * dx + dz * dz > within * within) return;
    body.requestJump();
  }

  final Vector3 _takeOff = Vector3.zero();

  /// What [steerTowardsFocus] or [steer] last asked for, so a brain can turn to
  /// face where it is going rather than where the focus is. Around a corner
  /// those are different directions, and an actor sliding sideways while
  /// staring through a wall is the tell that gives a flow field away.
  Vector3 get heading => _wish;

  void turnTowards(Actor actor, double x, double z, double dt) {
    if (x == 0.0 && z == 0.0) return;
    if (actor.facing == null) return;
    actor.yaw = turnedTowards(
      actor.yaw,
      math.atan2(-x, -z),
      actor.turnRate * dt,
    );
  }

  /// Whether an actor has a clear line to the focus.
  ///
  /// Against the level only. A ray that stopped on another actor would mean a
  /// crowd blinds itself, and two of them standing in a doorway would each wait
  /// for the other to move.
  bool canSee(Actor actor) => canSeePoint(actor, _focus);

  /// Whether there is a clear line from [actor]'s eye to [point].
  ///
  /// The general form of [canSee], which is that with the focus. Split out
  /// because an actor may care about something that is not what everybody else
  /// is looking at — the one it has turned on, the noise it went to look at —
  /// and a brain that could only ask about the focus had to charge blind at
  /// anything else.
  bool canSeePoint(Actor actor, Vector3 point) {
    final body = actor.body;
    // Nothing to see from. False rather than true: a brain that asks and gets
    // an unconditional yes charges at a player through a wall.
    if (body == null || !actor.eyeLevel(_eye)) return false;
    _aim
      ..setFrom(point)
      ..sub(_eye);
    final distance = _aim.length;
    if (distance < Tolerance.sameSurface) return true;
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

  /// The system's own state, which no component carries.
  ///
  /// **Everything else here is on an entity, and [EcsWorld.save] finds it.**
  /// These four are not: they belong to the system rather than to any actor,
  /// so a genre that saved its whole ECS still restored with the schedule and
  /// the aim reset.
  ///
  /// What that costs is small and real. [_tick] drives the think throttle, so
  /// restoring at zero re-phases every actor beyond [closeRange] — the same
  /// monsters, thinking on a different beat than the run that was saved, which
  /// is enough for a determinism check to stop matching. [_lastFocus] and its
  /// flag are what [focusVelocity] is measured from, so a restore without them
  /// spends its first step believing the player is standing still, and
  /// anything that leads a shot fires where the player already is not.
  ///
  /// A determinism test that restores into the *same* system cannot see any of
  /// this. Only one that loads the level again can, which is the documented
  /// use.
  Map<String, Object?> save() => <String, Object?>{
    'tick': _tick,
    if (_hasLastFocus)
      'lastFocus': <double>[_lastFocus.x, _lastFocus.y, _lastFocus.z],
  };

  void restore(Object? from) {
    if (from is! Map) return;
    final tick = from['tick'];
    if (tick is num) _tick = tick.toInt();
    _hasLastFocus = readVector(from['lastFocus'], _lastFocus);
    // Not saved: it is derived from the two fields above on the next step, and
    // a velocity restored without the position it was measured from is a
    // number with nothing behind it.
    _focusVelocity.setZero();
  }
}
