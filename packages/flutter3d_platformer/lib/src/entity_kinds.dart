import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'blocks.dart';
import 'checkpoint.dart';
import 'crate.dart';
import 'enemy.dart';
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

  /// A platform that gives way under you.
  static const String crumbling = 'crumbling';

  /// A block a ground pound breaks.
  static const String breakable = 'breakable';

  /// A ladder, or — with a swing on it — a rope.
  static const String climbable = 'climbable';

  /// A lamp on a post: something to see by, and something to see.
  static const String lamp = 'lamp';

  /// Something that walks a route and hurts on contact.
  static const String enemy = 'enemy';
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
    final rail = entity.string('follows');
    if (rail != null && scope.level.named(rail) == null) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'rides "$rail", which no entity in this level is named',
          where: scope.describe(entity),
        ),
      );
    }
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
        follows: entity.string('follows'),
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
      const CrumblingKind(),
      const BreakableKind(),
      const ClimbableKind(),
      // The engine's own kind, named by this game. `LightFixtureKind` stopped
      // being abstract precisely so a genre could say `lamp` without the engine
      // knowing the word.
      const EnemyKind(),
      LightFixtureKind(
        PlatformerEntities.lamp,
        defaultBehaviour: const FlameFlicker(),
        defaultSize: Vector3(0.4, 1.6, 0.4),
      ),
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

/// A platform that gives way. See [Crumbling].
final class CrumblingKind extends EntityKind {
  const CrumblingKind() : super(PlatformerEntities.crumbling);

  static final Vector3 defaultSize = Vector3(3.0, 0.4, 3.0);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final delay = entity.number('delay');
    if (delay != null && delay <= 0.0) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'gives way after $delay seconds, which is a platform nobody can '
          'stand on for long enough to notice',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final collider = place(entity, context, kind: ColliderKind.static,
        fallbackSize: defaultSize);
    final crumbling = context.mechanisms.add(
      Crumbling(
        name: entity.name,
        collider: collider,
        delay: entity.number('delay') ?? 0.5,
        gone: entity.number('gone') ?? 2.5,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: crumbling,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

/// A block a ground pound breaks. See [Breakable].
final class BreakableKind extends EntityKind {
  const BreakableKind() : super(PlatformerEntities.breakable);

  static final Vector3 defaultSize = Vector3(2.0, 2.0, 2.0);

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final collider = place(entity, context, kind: ColliderKind.static,
        fallbackSize: defaultSize);
    final block = context.mechanisms.add(
      Breakable(name: entity.name, collider: collider),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: block,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

/// A ladder, or a rope. See [Climbable].
final class ClimbableKind extends EntityKind {
  const ClimbableKind() : super(PlatformerEntities.climbable);

  /// Narrow and tall: a ladder is a line you stand on, not a room.
  static final Vector3 defaultSize = Vector3(1.0, 6.0, 1.0);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final size = entity.vector('size') ?? defaultSize;
    if (size.y < 2.0) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.warning,
          'is ${size.y} m tall, which is a ladder shorter than the runner '
          'climbing it',
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
    final climbable = context.mechanisms.add(
      Climbable(
        name: entity.name,
        collider: collider,
        climbSpeed: entity.number('speed') ?? 4.0,
        swing: entity.number('swing') ?? 0.0,
        period: entity.number('period') ?? 2.4,
        phase: entity.number('phase') ?? 0.0,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: climbable,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}

/// Something that walks a route. See [Patrol] and [Leaper].
///
/// The route is the entity's own position followed by whatever `route` lists,
/// so the simplest enemy a level can author is a position and one more point.
/// A `kind` of `leaper` jumps the gaps in that route instead of turning at
/// them.
final class EnemyKind extends EntityKind {
  const EnemyKind() : super(PlatformerEntities.enemy);

  /// Shorter than the runner, so a stomp reads as landing *on* something.
  static final Vector3 defaultSize = Vector3(0.7, 0.7, 0.7);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final route = entity.properties['route'];
    if (route is! List || route.isEmpty) {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'has no "route", so it is a thing standing in one place — which is a '
          'hazard, and cheaper',
          where: scope.describe(entity),
        ),
      );
    }
    final kind = entity.string('kind');
    if (kind != null && kind != 'patrol' && kind != 'leaper') {
      out.add(
        LevelIssue(
          LevelIssueSeverity.error,
          'is a "$kind", and this game knows "patrol" and "leaper"',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final actors = context.actors;
    final rows = entity.properties['route'];
    if (rows is! List || rows.isEmpty) return;

    final route = <Vector3>[entity.position.clone()];
    for (final row in rows) {
      if (row is List && row.length >= 3) {
        route.add(Vector3(
          (row[0] as num).toDouble(),
          (row[1] as num).toDouble(),
          (row[2] as num).toDouble(),
        ));
      }
    }
    if (route.length < 2) return;

    final size = entity.vector('size') ?? defaultSize;
    final body = CharacterController(
      world: context.world,
      shape: CollisionBox(size / 2.0),
      // The document points at the floor, as it does for everything else.
      position: entity.position + Vector3(0.0, size.y / 2.0, 0.0),
      layer: CollisionLayers.monster,
    );

    final speed = entity.number('speed') ?? 0.55;
    final actor = actors.spawn(
      body: body,
      health: Health(entity.number('health') ?? 20.0),
      facing: Facing(),
      brain: entity.string('kind') == 'leaper'
          ? Leaper(route: route, speed: speed)
          : Patrol(route: route, speed: speed),
    );

    context.reveal(entity, collider: body.collider, size: size);
    // So a stomp can find what it landed on: the runner reads `ground.userData`
    // and everything else in this genre puts its own mechanism there.
    body.collider.userData = actor;
  }
}
