import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'chase_brain.dart';
import 'combat/weapon_behaviour.dart';
import 'monster_def.dart';

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
