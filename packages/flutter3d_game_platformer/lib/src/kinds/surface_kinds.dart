import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
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
  /// The kind, under the type `PlatformerEntities.oneWay`.
  const OneWayKind() : super(PlatformerEntities.oneWay);

  /// Thin, because thickness is what a player misjudges when jumping through.
  static Vector3 get defaultSize => Vector3(4.0, 0.3, 4.0);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    final size = entity.vector('size');
    if (size != null && size.y > 0.6) {
      out.add(
        LevelIssue(
          Severity.warning,
          'is ${size.y} m thick, and a one-way platform that thick is one a '
          'player lands inside of before they are through it',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
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
  /// The kind, under the type `PlatformerEntities.conveyor`.
  const ConveyorKind() : super(PlatformerEntities.conveyor);

  /// The belt's size in metres when the entity gives none: four wide, eight
  /// long and 0.4 thick.
  static Vector3 get defaultSize => Vector3(4.0, 0.4, 8.0);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    final flow = entity.vector('flow');
    if (flow == null) {
      out.add(
        LevelIssue(
          Severity.error,
          'has no "flow", so it is a floor that carries nobody anywhere',
          where: scope.describe(entity),
        ),
      );
      return;
    }
    if (flow.length < 1e-6) {
      out.add(
        LevelIssue(
          Severity.warning,
          'flows nowhere',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
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
  /// The kind, under the type `PlatformerEntities.crumbling`.
  const CrumblingKind() : super(PlatformerEntities.crumbling);

  /// The platform's size in metres when the entity gives none: three
  /// across and 0.4 thick.
  static Vector3 get defaultSize => Vector3(3.0, 0.4, 3.0);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    final delay = entity.number('delay');
    if (delay != null && delay <= 0.0) {
      out.add(
        LevelIssue(
          Severity.error,
          'gives way after $delay seconds, which is a platform nobody can '
          'stand on for long enough to notice',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
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
        delaySeconds: entity.number('delay') ?? 0.5,
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
