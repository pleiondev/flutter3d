import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import '../collectible.dart';
import '../platformer_entities.dart';

final class CollectibleKind extends EntityKind {
  /// A player has to be able to get to one of these. See
  /// [EntityKind.mustBeReachable] — and the fourteen that were inside walls.
  @override
  bool get mustBeReachable => true;
  const CollectibleKind() : super(PlatformerEntities.collectible);

  static Vector3 get defaultSize => Vector3(0.5, 0.5, 0.5);

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
