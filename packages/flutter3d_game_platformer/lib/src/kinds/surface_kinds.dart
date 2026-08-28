import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import '../blocks.dart';
import '../platformer_entities.dart';
import '../surfaces.dart';

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
  static Vector3 get defaultSize => Vector3(4.0, 0.3, 4.0);

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

  static Vector3 get defaultSize => Vector3(4.0, 0.4, 8.0);

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

  static Vector3 get defaultSize => Vector3(3.0, 0.4, 3.0);

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
    final collider = place(
      entity,
      context,
      kind: ColliderKind.static,
      fallbackSize: defaultSize,
    );
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
