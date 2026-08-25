import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import '../checkpoint.dart';
import '../platformer_entities.dart';

final class CheckpointKind extends EntityKind {
  const CheckpointKind() : super(PlatformerEntities.checkpoint);

  static Vector3 get defaultSize => Vector3(1.5, 2.5, 1.5);

  /// What is drawn: a post, whatever the trigger's size is.
  static Vector3 get markerSize => Vector3(0.35, 2.2, 0.35);

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
