/// The parts of a first-person shooter that are not parts of an engine.
///
/// **Not exported from `flutter3d_game.dart`.** A game imports this by name if
/// it is a shooter, and a platformer does not — which is the whole reason the
/// file exists. Everything here used to live in `lib/src/`, where it meant the
/// engine knew what a monster was, what an alert pause was, and that being hurt
/// involves a chance of flinching.
///
/// What the engine keeps is in `actors/`: a body that walks, health that runs
/// out, turning, steering round corners, a line-of-sight test, and a [Brain]
/// that decides. This is one brain.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'flutter3d_game.dart';

/// What this game's monsters may be, as words in a level document.
///
/// `EntityTypes` holds the format's own vocabulary — spawn, door, trigger,
/// exit. `monster` is not the format's; it is a shooter's, the same way `torch`
/// is furniture. It lives beside the kind that implements it.
abstract final class ShooterEntities {
  static const String monster = 'monster';
}

/// What a monster is doing.
///
/// An enum with a switch, deliberately, and **only because it is in here**. Six
/// states that share every transition — anything can be hurt, anything hurt
/// enough dies, anything that sees the player chases them — would be six
/// classes repeating one another's rules. That trade is fine for one brain in
/// one game's own library; it was not fine in an engine, where it meant every
/// other kind of enemy anybody wrote had to pretend to have an `alert` state.
enum MonsterState { idle, alert, chase, attack, hurt, dead }

/// Everything about a kind of monster that does not change.
///
/// Numbers, plus the weapon it attacks with. Reusing `WeaponDef` rather than
/// inventing a parallel notion of a monster attack: an attack has damage, a
/// rate, a range and a way of arriving, which is a weapon — and it means a
/// monster that throws fireballs gets the projectile system, the blast falloff
/// and the line-of-sight check without a line of new code.
final class MonsterDef {
  const MonsterDef({
    required this.name,
    required this.health,
    required this.speed,
    required this.attack,
    required this.radius,
    required this.height,
    this.sightRange = 26.0,
    this.hurtDuration = 0.25,
    this.alertDuration = 0.35,
    this.turnRate = 6.0,
    this.painChance = 1.0,
    this.painCooldown = 0.2,
  });

  final String name;
  final double health;
  final double speed;
  final WeaponDef attack;
  final double radius;
  final double height;

  /// How far it can notice the player.
  final double sightRange;

  /// How long a stagger lasts. Long enough to read as a reaction, short enough
  /// that it cannot be used to stun-lock something to death.
  final double hurtDuration;

  /// How long it hesitates after noticing before it comes. A monster that
  /// snaps to face the player the instant it sees them reads as a turret.
  final double alertDuration;

  final double turnRate;

  /// How often being hit staggers it.
  ///
  /// Not always: something that flinches at every pellet can be held in place
  /// by a shotgun and never reaches the player, which turns the hardest enemy
  /// into the easiest.
  final double painChance;

  /// How long after a stagger before it can be staggered again.
  final double painCooldown;
}

/// Sees the player, hesitates, comes for them, and hits them.
///
/// The whole of the AI this repository's own game has, and the reason the
/// engine no longer contains it: none of these six states means anything to a
/// platformer, a racing game or a stealth game, and all three of those still
/// want the body, the health, the turning and the route-finding that
/// `ActorSystem` provides.
final class ChaseBrain extends Brain {
  ChaseBrain({required this.def, required this.shot});

  final MonsterDef def;

  /// Shared by every monster in the level: it is a way of firing, not a thing
  /// that is fired.
  final WeaponShot shot;

  MonsterState state = MonsterState.idle;

  /// Seconds in the current state, for animation and for timing out of
  /// [MonsterState.hurt] and [MonsterState.alert].
  double stateTime = 0.0;

  double attackCooldown = 0.0;
  double painCooldown = 0.0;

  /// True once it has noticed the player, and it never goes back to false.
  ///
  /// A monster that forgets and re-notices produces the alert hesitation over
  /// and over, which reads as a stutter rather than as caution.
  bool hasNoticed = false;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _aim = Vector3.zero();

  @override
  void think(Mind it) {
    switch (state) {
      case MonsterState.dead:
      case MonsterState.hurt:
        // Staggered, and not making decisions.
        return;

      case MonsterState.idle:
        if (it.distance <= def.sightRange && it.canSee()) {
          _enter(MonsterState.alert);
        }

      case MonsterState.alert:
        if (stateTime >= def.alertDuration) _enter(MonsterState.chase);

      case MonsterState.chase:
        if (it.distance <= def.attack.range && it.canSee()) {
          _enter(MonsterState.attack);
        }

      case MonsterState.attack:
        // Left as soon as the player is out of reach, so a monster does not
        // stand swinging at nothing.
        if (it.distance > def.attack.range * 1.15) _enter(MonsterState.chase);
    }
  }

  @override
  void act(Mind it) {
    stateTime += it.dt;
    attackCooldown = math.max(0.0, attackCooldown - it.dt);
    painCooldown = math.max(0.0, painCooldown - it.dt);

    switch (state) {
      case MonsterState.idle:
      case MonsterState.dead:
        break;

      case MonsterState.hurt:
        if (stateTime >= def.hurtDuration) _enter(MonsterState.chase);

      case MonsterState.alert:
        it.turnTowards(it.toFocus.x, it.toFocus.z);

      case MonsterState.chase:
        it.steerTowardsFocus();
        // Facing where it is going rather than where the player is. Around a
        // corner those are different directions, and a monster sliding
        // sideways while staring through a wall is the tell that gives a flow
        // field away.
        final heading = it.system.heading;
        it.turnTowards(heading.x, heading.z);

      case MonsterState.attack:
        it.turnTowards(it.toFocus.x, it.toFocus.z);
        if (attackCooldown <= 0.0) _attack(it);
    }
  }

  @override
  void onHurt(Mind it, double amount) {
    // Being shot is how a monster notices someone it could not see.
    hasNoticed = true;
    if (state == MonsterState.idle) _enter(MonsterState.chase);
    if (painCooldown <= 0.0 &&
        state != MonsterState.hurt &&
        it.random.nextDouble() < def.painChance) {
      _enter(MonsterState.hurt);
      painCooldown = def.hurtDuration + def.painCooldown;
      // Recorded after the roll, so a caller can tell a monster that flinched
      // from one that took the hit and kept coming — which is the difference
      // between a grunt and a scream.
      it.system.hurtThisStep.last.staggered = true;
    }
  }

  @override
  void onDeath(Mind it) => _enter(MonsterState.dead);

  void _attack(Mind it) {
    final weapon = def.attack;
    attackCooldown = weapon.cooldownSeconds;

    if (!it.actor.eyeLevel(_eye)) return;
    _aim
      ..setFrom(it.toFocus)
      ..y = 0.0;
    if (_aim.length2 < 1e-6) return;
    _aim.normalize();
    // Aim slightly up at the player's head rather than dead level, or a
    // fireball launched from chest height sails under them on a slope.
    _aim.y = (it.toFocus.y * 0.15).clamp(-0.4, 0.4);
    _aim.normalize();

    shot.begin(weapon, _eye, _aim, shooter: it.actor.body?.collider);
    weapon.behaviour.deliver(shot);

    // A melee swing lands immediately and reports what it reached; a projectile
    // reports nothing and arrives later, through the projectile system.
    for (final hit in shot.hits) {
      if (hit.collider == it.focusBody) {
        it.system.damageToFocusThisStep += hit.damage;
      }
    }
  }

  void _enter(MonsterState next) {
    if (state == next) return;
    state = next;
    stateTime = 0.0;
    if (next == MonsterState.alert || next == MonsterState.chase) {
      hasNoticed = true;
    }
  }

  @override
  Map<String, Object?> save() => <String, Object?>{
    'state': state.name,
    'stateTime': stateTime,
    'attackCooldown': attackCooldown,
    'painCooldown': painCooldown,
    'noticed': hasNoticed,
  };

  @override
  void restore(Map<String, Object?> from) {
    final named = from['state'];
    for (final value in MonsterState.values) {
      if (value.name == named) state = value;
    }
    stateTime = (from['stateTime'] as num?)?.toDouble() ?? 0.0;
    attackCooldown = (from['attackCooldown'] as num?)?.toDouble() ?? 0.0;
    painCooldown = (from['painCooldown'] as num?)?.toDouble() ?? 0.0;
    hasNoticed = from['noticed'] == true;
  }
}

/// What this game's monsters are, and how one becomes an [Actor].
///
/// The catalog is given rather than reached for, which is the rule the whole
/// content seam follows: a second shooter brings its own bestiary and gets none
/// of this one's.
final class Bestiary {
  Bestiary({required this.actors, required this.shot, required this.catalog});

  final ActorSystem actors;

  /// One way of firing, shared by every monster in the level.
  final WeaponShot shot;

  final Map<String, MonsterDef> catalog;

  Actor spawn(MonsterDef def, Vector3 position, {double yaw = 0.0}) {
    return actors.spawn(
      body: CharacterController(
        world: actors.world,
        shape: CollisionCapsule(
          radius: def.radius,
          halfHeight: math.max(0.01, def.height / 2.0 - def.radius),
        ),
        position: position,
        layer: CollisionLayers.monster,
        tuning: MovementTuning(
          walkSpeed: def.speed,
          sprintSpeed: def.speed,
          // No jumping and no coyote time: a monster that leaves the ground
          // is one that has walked off something, and it should simply fall.
          jumpSpeed: 0.0,
          coyoteTime: 0.0,
          jumpBufferTime: 0.0,
        ),
      ),
      health: Health(def.health),
      brain: ChaseBrain(def: def, shot: shot),
      // A monster has all four. Something else in the same system may have one
      // — see `ActorSystem.spawn`.
      facing: Facing(yaw: yaw, turnRate: def.turnRate),
    );
  }
}

/// Spawns whatever the bestiary says a monster can be.
final class MonsterKind extends EntityKind {
  MonsterKind(this.catalog, {this.bestiary}) : super(ShooterEntities.monster);

  /// What a `kind` string may name. Enough to **validate** a document, which is
  /// something a level editor and a loader that has not built a world yet both
  /// have to do before anything can be brought to life.
  final Map<String, MonsterDef> catalog;

  /// Where a monster goes when one is spawned, once there is a world to put it
  /// in. Settable, so that one registry validates a level and then spawns it —
  /// two registries could disagree about what a document may contain, which is
  /// the failure this seam was built to remove.
  Bestiary? bestiary;

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final bestiary = this.bestiary;
    if (bestiary == null) return;
    final def = catalog[entity.string('kind')];
    // Already an error from validate, and a level with errors does not load —
    // but a tool can spawn from a broken document deliberately, and crashing on
    // it would be the wrong answer.
    if (def == null) return;

    final actor = bestiary.spawn(
      def,
      // Authored where the feet go, which is the only place an author can see;
      // the body is positioned by its centre.
      entity.position + Vector3(0.0, def.height / 2.0, 0.0),
      yaw: entity.yaw,
    );
    context.onActorSpawned?.call(actor);
  }

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final kind = entity.string('kind');
    if (kind == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "kind", so nothing knows what to spawn',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (!catalog.containsKey(kind)) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'is a "$kind", which this game has never heard of',
          where: scope.describe(entity),
        ),
      );
    }
  }
}
