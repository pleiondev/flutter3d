import 'package:vector_math/vector_math.dart';

import '../actors/monster.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import '../world/gift.dart';
import '../world/light_fixture.dart';
import '../world/mover.dart';
import '../world/signals.dart';
import 'level.dart';
import 'level_issue.dart';
import 'spawn_context.dart';
import '../physics/layers.dart';

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
/// The vocabulary of the *format*, which is not everything a level may contain:
/// a game adds its own types and names them itself. `torch`, `lamp` and
/// `window` were here until the day this package stopped being one game's — see
/// `sample.dart`, which owns those three and the kinds behind them.
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
  static const String platform = 'platform';
  static const String button = 'button';
  static const String trigger = 'trigger';
  static const String note = 'note';
  static const String exit = 'exit';
}

// MARK: - The kinds

final class PlayerSpawnKind extends EntityKind {
  const PlayerSpawnKind() : super(EntityTypes.playerSpawn);
}

/// Spawns whatever the game says a monster can be.
///
/// **The catalog is given, not reached for.** This class used to read the
/// global `Monsters.byName`, which meant a level could only contain the three
/// monsters this repository's own game ships with — and that a second game
/// would validate its own levels against somebody else's roster. The catalog
/// is now the one thing that decides both what spawns and what validates, so
/// the two cannot disagree.
final class MonsterKind extends EntityKind {
  const MonsterKind(this.catalog) : super(EntityTypes.monster);

  /// What a `kind` string may name, and what it becomes.
  final Map<String, MonsterDef> catalog;

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final def = catalog[entity.string('kind')];
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

  /// What this kind will accept, which is exactly what it can spawn.
  ///
  /// It was a second literal set for a while — `{'runner', 'shooter', 'tank'}`
  /// beside `Monsters.byName` — two lists that had to agree with nothing making
  /// them. Reading the catalog removes that failure mode rather than testing
  /// for it: a test asserting two lists agree cannot fail once they are one
  /// list, which is the wrong artefact.
  Iterable<String> get kinds => catalog.keys;

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

/// Something on the floor that gives what the game says it gives.
///
/// The registry is given rather than reached for, for the same reason
/// [MonsterKind]'s catalog is: it decides both what a document may ask for and
/// what picking it up does, so the two cannot drift, and a game whose pickups
/// are not this one's can say so.
final class PickupKind extends EntityKind {
  const PickupKind(this.gifts) : super(EntityTypes.pickup);

  /// What a `gives` string may name, and what it grants.
  final GiftRegistry gifts;

  /// A panel of light on the floor, roughly the size of what it represents.
  static final Vector3 defaultSize = Vector3(0.45, 0.45, 0.45);

  /// What a document may ask for, taken from the registry rather than listed
  /// again here: two lists of the same names is one list too many.
  Iterable<String> get gives => gifts.names;

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
    if (!gifts.knows(what)) {
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

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final gift = gifts[entity.string('gives') ?? ''];
    if (gift == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.pickup,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final pickup = context.mechanisms.add(
      Pickup(
        name: entity.name,
        gift: gift,
        amount: entity.number('amount') ?? gift.defaultAmount,
        detail: entity.string('color'),
        collider: collider,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: pickup,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

final class KeyKind extends EntityKind {
  const KeyKind() : super(EntityTypes.key);

  /// Small enough to walk past without collecting by accident, big enough to
  /// walk into on purpose.
  static final Vector3 defaultSize = Vector3(0.4, 0.4, 0.4);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireText(entity, scope, out, 'color');
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final colour = entity.string('color');
    if (colour == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.pickup,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final pickup = context.mechanisms.add(
      Pickup(
        name: entity.name,
        gift: const KeyGift(),
        amount: 1.0,
        detail: colour,
        collider: collider,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: pickup,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

final class DoorKind extends EntityKind {
  const DoorKind() : super(EntityTypes.door);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireKeyExists(entity, scope, out);
    requireTravel(entity, scope, out);
    requireSize(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final travel = entity.vector('travel');
    if (travel == null) return;
    final collider = place(entity, context, kind: ColliderKind.kinematic);
    final door = context.mechanisms.add(
      Door(
        name: entity.name,
        collider: collider,
        travel: travel,
        speed: entity.number('speed') ?? Door.defaultSpeed,
        wait: entity.number('wait') ?? Door.defaultWait,
        key: entity.string('key'),
      ),
    );
    context.reveal(entity, collider: collider, mechanism: door);
  }
}

final class LiftKind extends EntityKind {
  const LiftKind() : super(EntityTypes.lift);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTravel(entity, scope, out);
    requireSize(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final travel = entity.vector('travel');
    if (travel == null) return;
    final collider = place(entity, context, kind: ColliderKind.kinematic);
    final lift = context.mechanisms.add(
      Lift(
        name: entity.name,
        collider: collider,
        travel: travel,
        speed: entity.number('speed') ?? Lift.defaultSpeed,
        wait: entity.number('wait') ?? Lift.defaultWait,
      ),
    );
    context.reveal(entity, collider: collider, mechanism: lift);
  }
}

/// Moves on its own timetable rather than waiting to be called.
final class PlatformKind extends EntityKind {
  const PlatformKind() : super(EntityTypes.platform);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTravel(entity, scope, out);
    requireSize(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final travel = entity.vector('travel');
    if (travel == null) return;
    final collider = place(entity, context, kind: ColliderKind.kinematic);
    final platform = context.mechanisms.add(
      Platform(
        name: entity.name,
        collider: collider,
        travel: travel,
        speed: entity.number('speed') ?? Platform.defaultSpeed,
        wait: entity.number('wait') ?? Platform.defaultWait,
      ),
    );
    // So a row of them does not move as one slab.
    platform.offsetBy(entity.number('phase') ?? 0.0);
    context.reveal(entity, collider: collider, mechanism: platform);
  }
}

final class ButtonKind extends EntityKind {
  const ButtonKind() : super(EntityTypes.button);

  /// A panel, not a block: a button is something on a wall.
  static final Vector3 defaultSize = Vector3(0.6, 0.6, 0.15);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTarget(entity, scope, out);
    requireKeyExists(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final target = entity.string('target');
    if (target == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final button = context.mechanisms.add(
      Button(
        name: entity.name,
        target: target,
        collider: collider,
        once: entity.flag('once'),
        key: entity.string('key'),
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: button,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

final class TriggerKind extends EntityKind {
  const TriggerKind() : super(EntityTypes.trigger);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireTarget(entity, scope, out);
    requireSize(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final target = entity.string('target');
    if (target == null) return;
    // Monsters can be allowed to set a trigger off, which is how an ambush
    // works, but the default is the player alone — otherwise the first monster
    // to wander through the room springs every trap in it.
    final who = entity.flag('anyone')
        ? CollisionLayers.player | CollisionLayers.monster
        : CollisionLayers.player;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: who,
    );
    // Invisible by design, so no fixture is reported.
    context.mechanisms.add(
      TriggerVolume(
        name: entity.name,
        target: target,
        collider: collider,
        once: entity.flag('once', orElse: true),
      ),
    );
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

/// Anything that gives off light and can be seen doing it.
///
/// One class for the three, because a torch, a lamp and a stained window
/// differ in what they look like and how they flicker — and both of those are
/// data. What they *do* is identical: own a light, and vary it.
/// A named kind of light, described by data rather than by a subclass.
///
/// It was abstract, with `TorchKind`, `LampKind` and `WindowKind` overriding
/// two getters each. Its own doc already said why that was one step too far:
/// *"a torch, a lamp and a stained window differ in what they look like and
/// how they flicker — and both of those are data"*. The abstraction was right
/// and only the instances were in the wrong package, so the three subclasses
/// are gone and a game names its own:
///
/// ```dart
/// LightFixtureKind('torch',
///     defaultBehaviour: const FlameFlicker(),
///     defaultSize: Vector3(0.22, 0.5, 0.22));
/// ```
final class LightFixtureKind extends EntityKind {
  LightFixtureKind(
    super.type, {
    required this.defaultBehaviour,
    required Vector3 defaultSize,
  }) : defaultSize = defaultSize.clone();

  /// How this kind behaves when the document does not say.
  final LightBehaviour defaultBehaviour;

  final Vector3 defaultSize;

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final light = entity.string('light');
    if (light == null) return;
    for (final candidate in scope.level.lights) {
      if (candidate.name == light) return;
    }
    out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        'drives the light "$light", which this level does not define',
        where: scope.describe(entity),
      ),
    );
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final fixture = context.mechanisms.add(
      LightFixture(
        name: entity.name,
        light: entity.string('light'),
        behaviour: _behaviourFor(entity),
        // From the position, so a row of torches never pulses in unison and
        // an author never has to remember to stagger them by hand.
        seed: entity.number('phase') ??
            (entity.position.x * 0.37 + entity.position.z * 0.11) % 1.0,
        enabled: entity.flag('on', orElse: true),
      ),
    );
    // No collider: this is something to look at, not something to walk into.
    context.reveal(
      entity,
      mechanism: fixture,
      size: entity.vector('size') ?? defaultSize,
    );
  }

  LightBehaviour _behaviourFor(EntityDef entity) {
    final depth = entity.number('flicker');
    if (depth == null) return defaultBehaviour;
    if (depth <= 0.0) return const SteadyLight();
    return FlameFlicker(depth: depth, rate: entity.number('rate') ?? 7.0);
  }
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
  /// The kinds any game on this level format needs, plus whatever else it has.
  ///
  /// **There is no `standard` registry any more**, and its absence is the
  /// point. It listed fourteen kinds, three of which — `torch`, `lamp` and
  /// `window` — were this repository's own game's furniture, and two of which
  /// reached for global rosters of its monsters and its pickups. A second game
  /// loading a level got all of it whether it wanted it or not, and validated
  /// its own documents against somebody else's vocabulary.
  ///
  /// What is left here is the vocabulary of the *format*: a spawn point, the
  /// three movers, a button, a trigger, a note, an exit, and the two kinds that
  /// need a catalog. Everything a game invents arrives through [extra]:
  ///
  /// ```dart
  /// EntityRegistry.forGame(
  ///   monsters: Monsters.byName,
  ///   gifts: sampleGifts,
  ///   extra: <EntityKind>[
  ///     LightFixtureKind('torch',
  ///         defaultBehaviour: const FlameFlicker(),
  ///         defaultSize: Vector3(0.22, 0.5, 0.22)),
  ///   ],
  /// );
  /// ```
  factory EntityRegistry.forGame({
    required Map<String, MonsterDef> monsters,
    required GiftRegistry gifts,
    Iterable<EntityKind> extra = const <EntityKind>[],
  }) =>
      EntityRegistry(<EntityKind>[
        const PlayerSpawnKind(),
        MonsterKind(monsters),
        PickupKind(gifts),
        const KeyKind(),
        const DoorKind(),
        const LiftKind(),
        const PlatformKind(),
        const ButtonKind(),
        const TriggerKind(),
        const NoteKind(),
        const ExitKind(),
        ...extra,
      ]);

  final Map<String, EntityKind> _byType;

  EntityKind? operator [](String type) => _byType[type];

  Iterable<String> get types => _byType.keys;

  bool knows(String type) => _byType.containsKey(type);
}
