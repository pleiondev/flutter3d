import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import '../blocks.dart';
import '../platformer_entities.dart';

/// A block a ground pound breaks. See [Breakable].
final class BreakableKind extends EntityKind {
  /// The kind, under the type `PlatformerEntities.breakable`.
  const BreakableKind() : super(PlatformerEntities.breakable);

  /// The block's size in metres when the entity gives none: two each way.
  static Vector3 get defaultSize => Vector3(2.0, 2.0, 2.0);

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
  /// The kind, under the type `PlatformerEntities.climbable`.
  const ClimbableKind() : super(PlatformerEntities.climbable);

  /// Narrow and tall: a ladder is a line you stand on, not a room.
  static Vector3 get defaultSize => Vector3(1.0, 6.0, 1.0);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    final size = entity.vector('size') ?? defaultSize;
    if (size.y < 2.0) {
      out.add(
        LevelIssue(
          Severity.warning,
          'is ${size.y} m tall, which is a ladder shorter than the runner '
          'climbing it',
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
