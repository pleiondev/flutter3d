/// Monsters: what they are, and the one brain this game gives them.
///
/// This was `flutter3d_game/lib/shooter.dart` — a file the game layer's barrel
/// deliberately did not export, so that a game had to ask for it by name. That
/// worked as a rule and not as a boundary: the file still sat in the engine's
/// package, and so did the weapons, the inventory and the step order it needs.
/// Now the boundary is the package, and the rule is enforced by resolution
/// rather than by discipline.
///
/// What the engine keeps is in its `actors/`: a body that walks, health that
/// runs out, turning, steering round corners, a line-of-sight test, and a
/// [Brain] that decides. This is one brain.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'combat/weapon.dart';
import 'combat/weapon_behaviour.dart';

/// What this game's monsters may be, as words in a level document.
///
/// `EntityTypes` holds the format's own vocabulary — spawn, door, trigger,
/// exit. `monster` is not the format's; it is a shooter's, the same way `torch`
/// is furniture. It lives beside the kind that implements it.
abstract final class ShooterEntities {
  static const String monster = 'monster';

  /// Two that used to be `EntityTypes`'. A pickup that gives health, armour or
  /// ammunition, and a note left on a wall to be read, are furniture of this
  /// genre rather than of the format — the same argument that moved `torch`,
  /// `lamp` and `window` out before them.
  ///
  /// `key` is not here, and the difference is worth the sentence: the *pickup*
  /// that grants a key is this genre's, but the word belongs to the format,
  /// because `LevelScope` gathers keys to check that a locked door names one
  /// that exists.
  static const String pickup = 'pickup';
  static const String note = 'note';

  /// A volume that counts as found when somebody walks into it.
  ///
  /// A word this genre owns for the same reason `monster` is: a racing game has
  /// no secrets and a platformer's are collectibles, which it already has.
  static const String secret = 'secret';
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

  /// Another actor this one has turned on, or null while its business is with
  /// the player.
  ///
  /// **Monsters could not hurt each other at all before this.** A monster's
  /// shot collected its hits and then counted the damage only if the thing hit
  /// was the focus — so a fireball crossing a room passed through anything
  /// standing in the way, and the classic thing a crowded room does was
  /// impossible.
  ///
  /// Kept as the actor rather than as a place, because the whole point is that
  /// it moves and can die: a quarrel with a corpse is dropped on the next
  /// thought.
  Actor? quarrel;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _aim = Vector3.zero();

  /// From this monster to whatever it is dealing with, and how far that is.
  ///
  /// The focus, unless it has a [quarrel]. Filled in at the top of every think
  /// and act so the state machine below reads one thing rather than branching
  /// on the quarrel five times.
  final Vector3 _toTarget = Vector3.zero();
  double _targetDistance = 0.0;

  /// Where it is aiming, for the shot and for [Bestiary] to read back.
  void _readTarget(Mind it) {
    final other = quarrel;
    final at = other?.position;
    final mine = it.actor.position;
    if (other == null || at == null || mine == null || !other.isAlive) {
      // A quarrel with something dead, or with something that has no body any
      // more, is over: back to the player.
      quarrel = null;
      _toTarget.setFrom(it.toFocus);
      _targetDistance = it.distance;
      return;
    }
    _toTarget
      ..setFrom(at)
      ..sub(mine);
    _targetDistance = _toTarget.length;
  }

  /// Whether it can see what it is dealing with.
  bool _canSeeTarget(Mind it) {
    final at = quarrel?.position;
    return at == null ? it.canSee() : it.canSeePoint(at);
  }

  @override
  void think(Mind it) {
    _readTarget(it);
    switch (state) {
      case MonsterState.dead:
      case MonsterState.hurt:
        // Staggered, and not making decisions.
        return;

      case MonsterState.idle:
        if (_targetDistance <= def.sightRange && _canSeeTarget(it)) {
          _enter(MonsterState.alert);
        }

      case MonsterState.alert:
        if (stateTime >= def.alertDuration) _enter(MonsterState.chase);

      case MonsterState.chase:
        if (_targetDistance <= def.attack.range && _canSeeTarget(it)) {
          _enter(MonsterState.attack);
        }

      case MonsterState.attack:
        // Left as soon as the player is out of reach, so a monster does not
        // stand swinging at nothing.
        if (_targetDistance > def.attack.range * 1.15) {
          _enter(MonsterState.chase);
        }
    }
  }

  @override
  void act(Mind it) {
    _readTarget(it);
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
        it.turnTowards(_toTarget.x, _toTarget.z);

      case MonsterState.chase:
        final other = quarrel?.position;
        if (other == null) {
          it.steerTowardsFocus();
        } else {
          // Straight at it, because the flow field is baked towards the focus
          // and following it would walk this monster to the player instead of
          // to the one it is fighting.
          it.steerTowards(other);
        }
        // Facing where it is going rather than where the target is. Around a
        // corner those are different directions, and a monster sliding
        // sideways while staring through a wall is the tell that gives a flow
        // field away.
        final heading = it.system.heading;
        it.turnTowards(heading.x, heading.z);

      case MonsterState.attack:
        it.turnTowards(_toTarget.x, _toTarget.z);
        if (attackCooldown <= 0.0) _attack(it);
    }
  }

  @override
  void onHurt(Mind it, double amount) {
    // Being shot is how a monster notices someone it could not see.
    hasNoticed = true;

    // **Whoever did it, if it was one of its own.** The player arrives here as
    // a `Player` and a lift as nothing at all; only another actor becomes a
    // quarrel, which is what keeps a monster from turning on the person it is
    // supposed to be chasing every time they land a shot.
    final culprit = it.hurtBy;
    if (culprit is Actor &&
        !identical(culprit, it.actor) &&
        culprit.isAlive) {
      quarrel = culprit;
      if (state == MonsterState.idle || state == MonsterState.alert) {
        _enter(MonsterState.chase);
      }
    }
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

  /// A shot, a door, something breaking. Worth getting up for.
  ///
  /// **It goes and looks; it does not open fire.** A monster that heard a
  /// shotgun two rooms away and immediately started shooting would be a monster
  /// that can see through walls, which is the failure this is supposed to fix
  /// rather than the one it should cause. `chase` walks it towards the focus,
  /// and what it finds when it arrives is the ordinary business of `think`.
  ///
  /// Only from `idle`. A monster already alert, chasing or swinging has nothing
  /// to learn from a noise, and one that is hurt is staggering — interrupting
  /// that would cancel the flinch the player just earned.
  @override
  void onNoise(Mind it, Vector3 at) {
    if (state != MonsterState.idle) return;
    hasNoticed = true;
    _enter(MonsterState.chase);
  }

  @override
  void onDeath(Mind it) => _enter(MonsterState.dead);

  void _attack(Mind it) {
    final weapon = def.attack;
    attackCooldown = weapon.cooldownSeconds;

    if (!it.actor.eyeLevel(_eye)) return;
    // At whatever it is dealing with — the player, or the one it has turned
    // on. Aiming at the focus regardless is what this did, and a monster in an
    // argument then swung at a player across the room and hit nothing at all.
    _readTarget(it);
    _aim.setFrom(_toTarget);
    // Led only when the target is the focus: the lead is built from the
    // system's own idea of how fast the focus is moving, and there is no such
    // number for anything else. A quarrel is close work anyway.
    if (quarrel == null) {
      _lead(it, weapon);
    } else {
      _ledHeight = _toTarget.y;
    }
    _aim.y = 0.0;
    if (_aim.length2 < 1e-6) return;
    final horizontal = _aim.length;
    _aim.normalize();
    // **A slope, not a height.** This used to be `height * 0.15`, which is a
    // fixed angle whatever the range: right enough at a metre and hopeless at
    // fourteen, where a fireball aimed a tenth of a unit upwards clears the
    // player's head by a metre and a half. Every shot the shooter has ever
    // fired across a room has gone over the top, and it looked like a monster
    // that was hard to be hit by rather than one that could not aim.
    //
    // Clamped, so something directly below does not fire straight up: at ±0.4
    // that is about twenty-two degrees, which reaches anything on a stair and
    // nothing on a ladder.
    _aim.y = horizontal < 1e-6
        ? 0.0
        : (_ledHeight / horizontal).clamp(-0.4, 0.4);
    _aim.normalize();

    shot.begin(weapon, _eye, _aim, shooter: it.actor.body?.collider);
    weapon.behaviour.deliver(shot);

    // A melee swing lands immediately and reports what it reached; a projectile
    // reports nothing and arrives later, through the projectile system.
    for (final hit in shot.hits) {
      if (hit.collider == it.focusBody) {
        // The focus is hurt by the game rather than here — it is the game that
        // knows what a player is and what armour does about it.
        it.system.damageToFocusThisStep += hit.damage;
        continue;
      }
      // **Everything else it hit, which used to be nobody.** This loop counted
      // the focus and dropped the rest on the floor, so a monster's shot passed
      // straight through anything standing in the way. `from` is what lets the
      // one that was hit know who to turn on.
      final target = hit.collider?.userData;
      if (target is Damageable) target.applyDamage(hit.damage, from: it.actor);
    }
  }

  /// Where the target will be, rather than where it is.
  ///
  /// **A fireball at a player running sideways used to miss every time.** The
  /// aim was `toFocus` — the vector to where they are *now* — and a projectile
  /// takes the better part of a second to cross a room, by which time they are
  /// somewhere else. That is not difficulty, it is the monster being unable to
  /// see what everyone else can, and it made the shooter the least dangerous
  /// thing in the game while looking exactly like the hardest to hit.
  ///
  /// First-order lead and no more: where the target is going, times how long
  /// the shot takes to get there, ignoring that leading changes the distance
  /// and therefore the time. Iterating that converges on a monster that never
  /// misses, which is a different bug.
  ///
  /// Only for projectiles. A hitscan arrives on the step it is fired and
  /// [WeaponDef.projectileSpeed] is zero for one, so the guard is the same
  /// question as "is there any flight time".
  void _lead(Mind it, WeaponDef weapon) {
    _ledHeight = it.toFocus.y;
    final speed = weapon.projectileSpeed;
    if (speed <= 0.0) return;
    final travel = it.distance / speed;
    final moving = it.system.focusVelocity;
    _aim
      ..x += moving.x * travel
      ..z += moving.z * travel;
    // Height is led as well, and then thrown away by the pitch clamp below —
    // kept because the clamp is about a fireball from chest height on a slope,
    // and a target that is falling is a different question the clamp should
    // still see the answer to.
    _ledHeight += moving.y * travel;
  }

  /// The vertical part of the lead, kept apart because the aim is flattened
  /// before the pitch is put back on it.
  double _ledHeight = 0.0;

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
        layer: CollisionLayers.actor,
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
