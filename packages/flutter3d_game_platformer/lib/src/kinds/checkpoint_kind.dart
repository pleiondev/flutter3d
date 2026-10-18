import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import '../checkpoint.dart';
import '../platformer_entities.dart';

/// A checkpoint in a level document. See [Checkpoint].
///
/// Needs an integer `order`: one without it is an error and spawns nothing.
/// `respawn` is where the runner reappears, the entity's position if absent,
/// and `marker` the size of the post drawn for it.
final class CheckpointKind extends EntityKind {
  /// The kind, under the type `PlatformerEntities.checkpoint`.
  const CheckpointKind() : super(PlatformerEntities.checkpoint);

  /// The trigger's size in metres when the entity gives none: wide and
  /// tall, so it is hard to miss.
  static Vector3 get defaultSize => Vector3(1.5, 2.5, 1.5);

  /// What is drawn: a post, whatever the trigger's size is.
  static Vector3 get markerSize => Vector3(0.35, 2.2, 0.35);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    if (entity.integer('order') == null) {
      out.add(
        LevelIssue(
          Severity.error,
          'has no "order", so nothing knows which checkpoint is further on',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
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
