import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import '../world/exit.dart';
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
  /// A key. The *pickup* that grants one is a shooter's — see
  /// `ShooterEntities` — but the word stays here, because [LevelScope]
  /// gathers keys to answer whether a locked door names one that exists,
  /// and locking a thing behind a token is not one genre's idea.
  static const String key = 'key';
  static const String door = 'door';
  static const String lift = 'lift';
  static const String platform = 'platform';
  static const String button = 'button';
  static const String trigger = 'trigger';
  static const String exit = 'exit';
}

// MARK: - The kinds

final class PlayerSpawnKind extends EntityKind {
  const PlayerSpawnKind() : super(EntityTypes.playerSpawn);
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
      MovingPlatform(
        name: entity.name,
        collider: collider,
        travel: travel,
        speed: entity.number('speed') ?? MovingPlatform.defaultSpeed,
        wait: entity.number('wait') ?? MovingPlatform.defaultWait,
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

final class ExitKind extends EntityKind {
  const ExitKind() : super(EntityTypes.exit);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireKeyExists(entity, scope, out);
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    // The player alone, and not because monsters would mind: a monster
    // wandering across the finish line would end the level from the far side
    // of the map with nobody watching.
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: CollisionLayers.player,
      fallbackSize: Vector3(1.5, 2.5, 1.5),
    );
    context.mechanisms.add(
      Exit(
        name: entity.name,
        collider: collider,
        next: entity.string('next'),
        message: entity.string('text'),
        key: entity.string('key'),
      ),
    );
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
  /// **There is no ready-made registry, and that is deliberate.**
  ///
  /// There was one, and it listed fourteen kinds: a spawn point, three movers,
  /// a button, a trigger, a note, an exit, a monster, a pickup, a key, and
  /// three kinds of lamp. A second game loading a level got every one of them.
  ///
  /// The first attempt at fixing that replaced it with a factory taking a
  /// monster catalog and a gift registry — which still says every game has
  /// monsters and pickups. They do not. A racing game has neither; a puzzle
  /// game has neither; a walking simulator has neither and no exit either.
  ///
  /// So this package offers *kinds*, and a game composes its own vocabulary
  /// out of the ones it wants:
  ///
  /// ```dart
  /// final kinds = EntityRegistry(<EntityKind>[
  ///   const PlayerSpawnKind(),
  ///   const DoorKind(),
  ///   MonsterKind(myMonsters),      // only if this game has monsters
  ///   MyOwnKind(),                  // and whatever it invents
  /// ]);
  /// ```
  ///
  /// `sample.dart` assembles the shooter's set, which is one call and is an
  /// example rather than a default.

  final Map<String, EntityKind> _byType;

  EntityKind? operator [](String type) => _byType[type];

  Iterable<String> get types => _byType.keys;

  bool knows(String type) => _byType.containsKey(type);
}
