import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import '../hazard.dart';
import '../platformer_entities.dart';

final class HazardKind extends EntityKind {
  const HazardKind() : super(PlatformerEntities.hazard);

  static Vector3 get defaultSize => Vector3(2.0, 1.0, 2.0);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    final rail = entity.string('follows');
    if (rail != null && scope.level.named(rail) == null) {
      out.add(
        LevelIssue(
          Severity.error,
          'rides "$rail", which no entity in this level is named',
          where: scope.describe(entity),
        ),
      );
    }
    final damage = entity.number('damage');
    if (damage != null && damage <= 0.0 && !entity.flag('instant')) {
      out.add(
        LevelIssue(
          Severity.warning,
          'is a hazard that does no damage',
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
