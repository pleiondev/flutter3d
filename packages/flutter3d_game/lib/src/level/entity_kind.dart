import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import '../math/tolerances.dart';
import '../physics/layers.dart';
import 'entity_def.dart';
import 'entity_types.dart';
import 'level_issue.dart';
import 'level_scope.dart';
import 'spawn_context.dart';

export 'entity_registry.dart';
export 'entity_types.dart';
export 'level_scope.dart';
export 'light_fixture_kind.dart';
export 'mover_kinds.dart';
export 'player_spawn_kind.dart';
export 'trigger_kinds.dart';

/// Everything one kind of level entity knows about itself.
///
/// ## Why this is a hierarchy and not a switch
///
/// An entity is a type name and a bag of properties, which is the right shape
/// for a format that has to survive an editor and thirty kinds of thing. It is
/// the wrong shape for code: without this, every job that treats kinds
/// differently — validating them, spawning them, drawing an editor form for
/// them — grows its own switch over the same eleven names, in a different file,
/// and the four switches drift.
///
/// So each kind is an object that owns its own rules, and the jobs ask the kind
/// rather than asking what the kind is. Adding a twelfth means writing one
/// class and registering it, and the compiler names every duty it still owes.
///
/// Two duties so far: checking an entity, and turning it into something that
/// exists. Both are the kind's own business, which is the whole reason this is
/// a hierarchy — the validator and the spawner each walk the entity list once
/// and ask, instead of each carrying its own switch over the same names.
abstract base class EntityKind {
  /// Whether a player has to be able to *get to* one of these.
  ///
  /// A coin inside a wall looks exactly like a coin nobody has taken yet, and
  /// fourteen of them shipped in two levels before anything asked. The check
  /// lives in the validator; the answer lives here, because "is this something
  /// the player collects" is a question about a kind and not about geometry —
  /// and because the engine must not learn the words `coin`, `crate` or `key`.
  ///
  /// False by default: a light fixture, a trigger volume and a spawn point are
  /// all perfectly happy inside solid rock.
  bool get mustBeReachable => false;
  const EntityKind(this.type);

  /// The string that appears in a level document.
  final String type;

  /// Checks one entity of this kind, in the context of the level around it.
  ///
  /// Reports rather than throws: a level with several problems should list all
  /// of them, and an editor has to be able to load a broken level in order to
  /// fix it.
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {}

  /// Brings this entity into the world.
  ///
  /// Does nothing by default, which is right for the kinds that are pure data
  /// — a spawn point is a coordinate somebody reads, and a torch is a light the
  /// level already carries.
  void spawn(EntityDef entity, SpawnContext context) {}

  /// Puts the box this entity brings with it into the world.
  ///
  /// On the base class for the same reason [requireTarget] is: five kinds place
  /// a box of their own, and five copies of the same six lines is five chances
  /// to get the layer wrong.
  Collider place(
    EntityDef entity,
    SpawnContext context, {
    required ColliderKind kind,
    int layer = CollisionLayers.world,
    int mask = CollisionLayers.all,
    Vector3? fallbackSize,
  }) {
    final size = entity.vector('size') ?? fallbackSize ?? Vector3.all(1.0);
    return context.world.add(
      Collider(
        shape: CollisionBox(size / 2.0),
        position: entity.position,
        kind: kind,
        layer: layer,
        mask: mask,
      ),
    );
  }

  /// Reports that an entity which has to occupy space does not say how much.
  void requireSize(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final size = entity.vector('size');
    if (size == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "size", so there would be nothing there',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (size.x <= 0.0 || size.y <= 0.0 || size.z <= 0.0) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has a size of ${size.x} x ${size.y} x ${size.z}',
          where: scope.describe(entity),
        ),
      );
    }
  }

  /// Reports that a named reference does not resolve.
  ///
  /// On the base class because half the kinds point at something, and each
  /// writing its own message would produce half a dozen wordings for one
  /// mistake.
  void requireTarget(
    EntityDef entity,
    LevelScope scope,
    List<LevelIssue> out, {
    bool optional = false,
  }) {
    final target = entity.string('target');
    if (target == null) {
      if (optional) return;
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "target", so it would do nothing',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (scope.level.named(target) == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'targets "$target", which no entity is named',
          where: scope.describe(entity),
        ),
      );
    }
  }

  /// Reports that a key this entity demands exists nowhere in the level.
  void requireKeyExists(
    EntityDef entity,
    LevelScope scope,
    List<LevelIssue> out,
  ) {
    final wanted = entity.string('key');
    if (wanted == null) return;
    if (scope.keys.contains(wanted)) return;
    out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        'needs the "$wanted" key, and no ${EntityTypes.key} entity in this '
        'level provides one',
        where: scope.describe(entity),
      ),
    );
  }

  /// Reports that a movement offset is missing or goes nowhere.
  void requireTravel(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final travel = entity.vector('travel');
    if (travel == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "travel" offset, so it has nowhere to go',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (travel.length < Tolerance.zeroLength) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'travels nowhere',
          where: scope.describe(entity),
        ),
      );
    }
  }

  void requireText(
    EntityDef entity,
    LevelScope scope,
    List<LevelIssue> out,
    String key,
  ) {
    final value = entity.string(key);
    if (value != null && value.isNotEmpty) return;
    out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        'has no "$key", so there would be nothing to show',
        where: scope.describe(entity),
      ),
    );
  }
}
