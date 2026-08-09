import 'package:vector_math/vector_math.dart';

import '../actors/monster.dart';
import 'level.dart';
import 'level_issue.dart';
import 'spawn_context.dart';

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
    if (travel.length < 1e-6) {
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

/// What an entity can see of the level it sits in.
///
/// Passed to [EntityKind.validate] rather than the whole [Level], so a kind can
/// answer "does this key exist" without walking every entity for each one — the
/// set is gathered once — and so what a kind is allowed to look at stays a
/// short, readable list.
final class LevelScope {
  LevelScope(this.level)
      : keys = <String>{
          for (final key in level.ofType(EntityTypes.key))
            if (key.string('color') != null) key.string('color')!,
        };

  final Level level;

  /// Every key colour some pickup in this level provides.
  final Set<String> keys;

  /// Where to look, for an issue message: `entities[4] door "north"`.
  String describe(EntityDef entity) {
    final index = level.entities.indexOf(entity);
    return 'entities[$index] ${entity.type}'
        '${entity.name == null ? '' : ' "${entity.name}"'}';
  }
}

/// The names a level document uses.
///
/// Kept as constants next to the kinds that implement them so a document, a
/// validator and an editor all spell them the same way.
abstract final class EntityTypes {
  static const String playerSpawn = 'player_spawn';
  static const String monster = 'monster';
  static const String pickup = 'pickup';
  static const String key = 'key';
  static const String door = 'door';
  static const String lift = 'lift';
  static const String button = 'button';
  static const String trigger = 'trigger';
  static const String note = 'note';
  static const String exit = 'exit';
  static const String torch = 'torch';
}

// MARK: - The kinds

final class PlayerSpawnKind extends EntityKind {
  const PlayerSpawnKind() : super(EntityTypes.playerSpawn);
}

final class MonsterKind extends EntityKind {
  const MonsterKind() : super(EntityTypes.monster);

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final def = Monsters.byName[entity.string('kind')];
    // Already an error from validate, and a level with errors does not load —
    // but a tool can spawn from a broken document deliberately, and crashing
    // on it would be the wrong answer.
    if (def == null) return;

    final monster = context.monsters.spawn(
      def,
      // Authored where the feet go, which is the only place an author can see;
      // the body is positioned by its centre.
      entity.position + Vector3(0.0, def.height / 2.0, 0.0),
      yaw: entity.yaw,
    );
    context.onMonsterSpawned?.call(monster);
  }

  /// The roster. A monster naming something else spawns nothing, so it is an
  /// error rather than a shrug.
  static const Set<String> kinds = <String>{'runner', 'shooter', 'tank'};

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final kind = entity.string('kind');
    if (kind == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "kind", so there is nothing to spawn',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (!kinds.contains(kind)) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'is a "$kind", which is not one of ${kinds.join(', ')}',
          where: scope.describe(entity),
        ),
      );
    }
  }
}

final class PickupKind extends EntityKind {
  const PickupKind() : super(EntityTypes.pickup);

  static const Set<String> gives = <String>{
    'health',
    'armour',
    'bullets',
    'shells',
    'rockets',
    'invulnerability',
    'berserk',
    'map',
  };

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final what = entity.string('gives');
    if (what == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "gives", so picking it up would do nothing',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (!gives.contains(what)) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'gives "$what", which nothing knows how to grant',
          where: scope.describe(entity),
        ),
      );
    }
    final amount = entity.number('amount');
    if (amount != null && amount <= 0.0) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'gives an amount of $amount',
          where: scope.describe(entity),
        ),
      );
    }
  }
}

final class KeyKind extends EntityKind {
  const KeyKind() : super(EntityTypes.key);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireText(entity, scope, out, 'color');
  }
}

final class DoorKind extends EntityKind {
  const DoorKind() : super(EntityTypes.door);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireKeyExists(entity, scope, out);
    requireTravel(entity, scope, out);
  }
}

final class LiftKind extends EntityKind {
  const LiftKind() : super(EntityTypes.lift);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTravel(entity, scope, out);
  }
}

final class ButtonKind extends EntityKind {
  const ButtonKind() : super(EntityTypes.button);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTarget(entity, scope, out);
    requireKeyExists(entity, scope, out);
  }
}

final class TriggerKind extends EntityKind {
  const TriggerKind() : super(EntityTypes.trigger);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTarget(entity, scope, out);
    final size = entity.vector('size');
    if (size == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "size", so there is no volume to step into',
          where: scope.describe(entity),
        ),
      );
    }
  }
}

final class NoteKind extends EntityKind {
  const NoteKind() : super(EntityTypes.note);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireText(entity, scope, out, 'text');
  }
}

final class ExitKind extends EntityKind {
  const ExitKind() : super(EntityTypes.exit);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireKeyExists(entity, scope, out);
  }
}

final class TorchKind extends EntityKind {
  const TorchKind() : super(EntityTypes.torch);
}

/// The kinds a build knows about, by name.
///
/// A registry rather than a hardcoded list inside the validator, so a game
/// built on this package can add its own without editing it — and so tests can
/// validate against a deliberately small set.
final class EntityRegistry {
  EntityRegistry(Iterable<EntityKind> kinds)
      : _byType = <String, EntityKind>{
          for (final kind in kinds) kind.type: kind,
        };

  /// Everything this game ships with.
  static final EntityRegistry standard = EntityRegistry(<EntityKind>[
    const PlayerSpawnKind(),
    const MonsterKind(),
    const PickupKind(),
    const KeyKind(),
    const DoorKind(),
    const LiftKind(),
    const ButtonKind(),
    const TriggerKind(),
    const NoteKind(),
    const ExitKind(),
    const TorchKind(),
  ]);

  final Map<String, EntityKind> _byType;

  EntityKind? operator [](String type) => _byType[type];

  Iterable<String> get types => _byType.keys;

  bool knows(String type) => _byType.containsKey(type);
}
