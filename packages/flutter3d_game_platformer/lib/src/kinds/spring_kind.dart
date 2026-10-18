import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import '../platformer_entities.dart';
import '../spring.dart';

/// A spring pad in a level document. See [Spring].
///
/// `speed` is how fast it throws, in metres per second, 15 if absent; a
/// speed of nought or less is an error.
final class SpringKind extends EntityKind {
  /// The kind, under the type `PlatformerEntities.spring`.
  const SpringKind() : super(PlatformerEntities.spring);

  /// Wide and flat: a pad you can miss is a pad that reads as broken.
  static Vector3 get defaultSize => Vector3(1.6, 0.4, 1.6);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    final speed = entity.number('speed');
    if (speed != null && speed <= 0.0) {
      out.add(
        LevelIssue(
          Severity.error,
          'throws at $speed, which is a pad that does nothing',
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
