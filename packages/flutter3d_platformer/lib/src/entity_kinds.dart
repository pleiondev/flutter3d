import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'checkpoint.dart';
import 'crate.dart';
import 'spring.dart';
import 'surfaces.dart';
import 'collectible.dart';
import 'hazard.dart';

/// The words a platformer's levels use beyond the format's own.
///
/// `EntityTypes` already covers the spawn point, doors, lifts, platforms,
/// buttons, triggers, exits and lights — every one of which a platformer wants
/// unchanged, which is the first evidence that the level format really was
/// written for levels rather than for one game.
abstract final class PlatformerEntities {
  static const String collectible = 'collectible';
  static const String hazard = 'hazard';
  static const String checkpoint = 'checkpoint';
  static const String crate = 'crate';
  static const String spring = 'spring';

  /// A platform you jump up through and land on top of.
  static const String oneWay = 'oneway';

  /// A floor that carries whoever stands on it.
  static const String conveyor = 'conveyor';
}

final class CollectibleKind extends EntityKind {
  const CollectibleKind() : super(PlatformerEntities.collectible);

  static final Vector3 defaultSize = Vector3(0.5, 0.5, 0.5);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireText(entity, scope, out, 'what');
    final howMany = entity.integer('count');
    if (howMany != null && howMany <= 0) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'gives $howMany of what it holds, so walking over it does nothing',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final what = entity.string('what');
    if (what == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.pickup,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final collectible = context.mechanisms.add(
      Collectible(
        name: entity.name,
        what: what,
        howMany: entity.integer('count') ?? 1,
        key: entity.string('key'),
        collider: collider,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: collectible,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

final class HazardKind extends EntityKind {
  const HazardKind() : super(PlatformerEntities.hazard);

  static final Vector3 defaultSize = Vector3(2.0, 1.0, 2.0);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final damage = entity.number('damage');
    if (damage != null && damage <= 0.0 && !entity.flag('instant')) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'is a hazard that does no damage',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final hazard = context.mechanisms.add(
      Hazard(
        name: entity.name,
        collider: collider,
        damagePerSecond: entity.number('damage') ?? 40.0,
        instant: entity.flag('instant'),
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: hazard,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

final class CheckpointKind extends EntityKind {
  const CheckpointKind() : super(PlatformerEntities.checkpoint);

  static final Vector3 defaultSize = Vector3(1.5, 2.5, 1.5);

  /// What is drawn: a post, whatever the trigger's size is.
  static final Vector3 markerSize = Vector3(0.35, 2.2, 0.35);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    if (entity.integer('order') == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "order", so nothing knows which checkpoint is further on',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final order = entity.integer('order');
    if (order == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final checkpoint = context.mechanisms.add(
      Checkpoint(
        name: entity.name,
        collider: collider,
        order: order,
        at: entity.vector('respawn') ?? entity.position,
      ),
    );
    // The volume is wide so that it is hard to miss; the *marker* is a post,
    // because a checkpoint drawn at the size of its trigger is an eight-metre
    // slab across the middle of the level, which is what the first build did.
    context.reveal(
      entity,
      collider: collider,
      mechanism: checkpoint,
      size: entity.vector('marker') ?? markerSize,
    );
  }
}

/// Everything a platformer's level may contain, format and genre together.
///
/// A game composes this itself — there is no default registry and that is the
/// point — but the eight the format ships are wanted verbatim, so listing them
/// here is the honest version of "and the usual".
EntityRegistry platformerRegistry({Dynamics? dynamics}) =>
    EntityRegistry(<EntityKind>[
      const PlayerSpawnKind(),
      const DoorKind(),
      const LiftKind(),
      const PlatformKind(),
      const ButtonKind(),
      const TriggerKind(),
      const ExitKind(),
      const CollectibleKind(),
      const HazardKind(),
      const CheckpointKind(),
      const KeyKind(),
      CrateKind(dynamics: dynamics),
      const SpringKind(),
      const OneWayKind(),
      const ConveyorKind(),
    ]);

/// What is true of a platformer's level whatever it contains.
///
/// One spawn to start at, one exit to reach. The shooter says the same two and
/// they are still not the format's, which is why [LevelRule] takes them as an
/// argument: a hub level with three exits is a perfectly good level and this
/// list is a game's opinion, not a law.
List<LevelRule> platformerRules() => const <LevelRule>[
      ExactlyOne(EntityTypes.playerSpawn),
      AtLeastOne(EntityTypes.exit),
    ];

final class SpringKind extends EntityKind {
  const SpringKind() : super(PlatformerEntities.spring);

  /// Wide and flat: a pad you can miss is a pad that reads as broken.
  static final Vector3 defaultSize = Vector3(1.6, 0.4, 1.6);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final speed = entity.number('speed');
    if (speed != null && speed <= 0.0) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'throws at $speed, which is a pad that does nothing',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.trigger,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final spring = context.mechanisms.add(
      Spring(
        name: entity.name,
        collider: collider,
        speed: entity.number('speed') ?? 15.0,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: spring,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

/// A key on the floor.
///
/// The type is the *format's* `key`, not one of this genre's, and that is not
/// an accident: `LevelScope` gathers keys to answer whether a locked door names
/// one that exists, so a game that invents its own word for them loses the
/// validator's help and ships levels with doors nothing opens.
///
/// What it spawns is an ordinary [Collectible] that also grants a key — the
/// walking-over-it half is identical and only where it lands differs.
final class KeyKind extends EntityKind {
  const KeyKind() : super(EntityTypes.key);

  static final Vector3 defaultSize = Vector3(0.5, 0.5, 0.5);

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
    final key = context.mechanisms.add(
      Collectible(
        name: entity.name,
        what: 'key',
        key: colour,
        collider: collider,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: key,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

/// A platform that is a floor from above and nothing from below.
///
/// An entity rather than a brush with a layer number in it. A brush could carry
/// the bit — `Brush.layer` exists and the level format can write it — but the
/// number would be a bare 64 in a document, meaning nothing to anybody reading
/// it, and the genre's own word for the thing belongs with the genre's other
/// words. What makes it work is [PlatformerLayers.oneWay] and the runner's
/// filter; this only puts the box on the right layer.
final class OneWayKind extends EntityKind {
  const OneWayKind() : super(PlatformerEntities.oneWay);

  /// Thin, because thickness is what a player misjudges when jumping through.
  static final Vector3 defaultSize = Vector3(4.0, 0.3, 4.0);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final size = entity.vector('size');
    if (size != null && size.y > 0.6) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'is ${size.y} m thick, and a one-way platform that thick is one a '
          'player lands inside of before they are through it',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final collider = place(
      entity,
      context,
      kind: ColliderKind.static,
      layer: PlatformerLayers.oneWay,
      fallbackSize: defaultSize,
    );
    context.reveal(
      entity,
      collider: collider,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

/// A floor that drags whatever stands on it.
///
/// The belt does not move — only its skin does — which is exactly what
/// `Collider.surfaceVelocity` says, and why a conveyor needed no mover, no
/// schedule and no mechanism at all. It is a static box with a number on it.
final class ConveyorKind extends EntityKind {
  const ConveyorKind() : super(PlatformerEntities.conveyor);

  static final Vector3 defaultSize = Vector3(4.0, 0.4, 8.0);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final flow = entity.vector('flow');
    if (flow == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "flow", so it is a floor that carries nobody anywhere',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (flow.length < 1e-6) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'flows nowhere',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final flow = entity.vector('flow');
    if (flow == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.static,
      fallbackSize: defaultSize,
    );
    collider.surfaceVelocity.setFrom(flow);
    context.reveal(
      entity,
      collider: collider,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}
