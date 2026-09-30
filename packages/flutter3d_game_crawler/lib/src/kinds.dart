/// What a crawl's level document may contain, and how each thing arrives.
///
/// The format's own kinds are used as they are: `player_spawn` is where a
/// hero starts, told which with a `slot` from nought to three; `door` with a
/// `key` and a `wait` of nought is a locked door; `exit` is the way out.
///
/// **Any key opens any door here**, but the validator still asks that some
/// `key` entity's `color` is the colour a door names, which is the format's
/// way of saying a locked door has a key somewhere. Give them one colour and
/// it holds. What
/// this genre adds is below — loot, generators and the monsters placed by
/// hand.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'generator.dart';
import 'horde.dart';
import 'loot.dart';
import 'monster_kind.dart';

/// The words a crawl's level document uses, beside the format's own.
abstract final class CrawlerEntities {
  static const String food = 'food';
  static const String key = EntityTypes.key;
  static const String potion = 'potion';
  static const String treasure = 'treasure';
  static const String generator = 'generator';
  static const String monster = 'monster';
}

/// The name a mechanism is saved under: the level's, or one made from its
/// type and where it stands.
///
/// **A save skips what has no name**, and a crawl is mostly things that
/// change — food eaten, generators broken. An author who did not name every
/// plate of food would find it all back on the table after a load. The place
/// is stable across loads of the same document, which is all a name has to be.
String _nameOf(EntityDef entity) {
  final p = entity.position;
  return entity.name ?? '${entity.type}@${p.x},${p.y},${p.z}';
}

/// Validates against [kinds] before there is a horde, and spawns into
/// [horde] once there is one — the same registry doing both, as the
/// platformer's crate kind is told where bodies go after there is a world.
abstract base class _MonsterSource extends EntityKind {
  _MonsterSource(super.type, this.kinds);

  final List<MonsterKind> kinds;

  /// Where what this spawns goes. Set by `stageCrawl` before spawning.
  Horde? horde;

  MonsterKind? kindOf(EntityDef entity) {
    final name = entity.string('kind');
    for (final kind in kinds) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    if (kindOf(entity) != null) return;
    out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        'is of kind "${entity.string('kind')}", and this crawl knows '
        '${kinds.map((MonsterKind k) => '"${k.name}"').join(', ')}',
        where: scope.describe(entity),
      ),
    );
  }

  Horde get _horde {
    final there = horde;
    if (there == null) {
      throw StateError('$type spawned before the registry was given a horde');
    }
    return there;
  }
}

/// A place monsters keep coming from. `kind`, and optionally `cap`,
/// `period`, `health` and `size`.
final class GeneratorKind extends _MonsterSource {
  GeneratorKind(List<MonsterKind> kinds)
    : super(CrawlerEntities.generator, kinds);

  static Vector3 get defaultSize => Vector3(1.0, 1.0, 1.0);

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final kind = kindOf(entity);
    if (kind == null) return;
    final size = entity.vector('size') ?? defaultSize;
    final collider = context.world.add(
      Collider(
        shape: CollisionBox.size(size),
        position: entity.position + Vector3(0.0, size.y / 2.0, 0.0),
      ),
    );
    final generator = context.mechanisms.add(
      Generator(
        name: _nameOf(entity),
        collider: collider,
        kind: kind,
        horde: _horde,
        cap: entity.integer('cap') ?? 12,
        period: entity.number('period') ?? 2.0,
        health: entity.number('health') ?? 60.0,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: generator,
      size: size,
    );
  }
}

/// A monster the level places by hand. `kind`.
final class MonsterEntityKind extends _MonsterSource {
  MonsterEntityKind(List<MonsterKind> kinds)
    : super(CrawlerEntities.monster, kinds);

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final kind = kindOf(entity);
    if (kind == null) return;
    final monster = _horde.spawn(
      kind,
      entity.position + Vector3(0.0, kind.height / 2.0, 0.0),
    );
    context.onActorSpawned?.call(monster);
  }
}

/// Loot of one sort, lying where the level puts it.
final class LootKind extends EntityKind {
  const LootKind(super.type, this.make);

  /// Builds the loot, under [name], from the entity and the trigger placed
  /// for it.
  final Loot Function(EntityDef entity, String name, Collider collider) make;

  /// A hero has to be able to walk to it.
  @override
  bool get mustBeReachable => true;

  static Vector3 get defaultSize => Vector3(0.6, 0.6, 0.6);

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.pickup,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final loot = context.mechanisms.add(
      make(entity, _nameOf(entity), collider),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: loot,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

/// Everything a crawl's level may contain: the format's spawn, doors, lifts,
/// buttons, triggers and exits, and this genre's loot, generators and
/// monsters of [kinds].
EntityRegistry crawlerRegistry({List<MonsterKind> kinds = MonsterKind.all}) =>
    EntityRegistry(<EntityKind>[
      const PlayerSpawnKind(),
      const DoorKind(),
      const LiftKind(),
      const ButtonKind(),
      const TriggerKind(),
      const ExitKind(),
      LootKind(
        CrawlerEntities.food,
        (EntityDef e, String name, Collider c) =>
            Food(name: name, collider: c, amount: e.number('amount') ?? 100.0),
      ),
      LootKind(
        CrawlerEntities.key,
        (EntityDef e, String name, Collider c) =>
            DoorKey(name: name, collider: c),
      ),
      LootKind(
        CrawlerEntities.potion,
        (EntityDef e, String name, Collider c) =>
            Potion(name: name, collider: c),
      ),
      LootKind(
        CrawlerEntities.treasure,
        (EntityDef e, String name, Collider c) =>
            Treasure(name: name, collider: c, worth: e.integer('worth') ?? 100),
      ),
      GeneratorKind(kinds),
      MonsterEntityKind(kinds),
    ]);

/// What is true of a crawl's level whatever it contains: somewhere for the
/// heroes to start and a way out.
List<LevelRule> crawlerRules() => const <LevelRule>[
  AtLeastOne(EntityTypes.playerSpawn),
  AtLeastOne(EntityTypes.exit),
];
