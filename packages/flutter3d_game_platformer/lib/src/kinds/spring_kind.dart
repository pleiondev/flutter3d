import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import '../platformer_entities.dart';
import '../spring.dart';

final class SpringKind extends EntityKind {
  const SpringKind() : super(PlatformerEntities.spring);

  /// Wide and flat: a pad you can miss is a pad that reads as broken.
  static Vector3 get defaultSize => Vector3(1.6, 0.4, 1.6);

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
