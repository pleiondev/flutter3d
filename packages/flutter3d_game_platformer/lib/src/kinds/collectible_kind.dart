import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Severity;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import '../collectible.dart';
import '../platformer_entities.dart';

/// A collectible in a level document. See [Collectible].
///
/// Needs a `what`, the purse kind it counts as; one without it spawns
/// nothing. `count` is how many it gives, one if absent, and a count of
/// nought or less is warned about. `key` makes it open a door too.
final class CollectibleKind extends EntityKind {
  /// A player has to be able to get to one of these. See
  /// [EntityKind.mustBeReachable] — and the fourteen that were inside walls.
  @override
  bool get mustBeReachable => true;

  /// The kind, under the type `PlatformerEntities.collectible`.
  const CollectibleKind() : super(PlatformerEntities.collectible);

  /// The trigger's size in metres when the entity gives none: half a metre
  /// each way.
  static Vector3 get defaultSize => Vector3(0.5, 0.5, 0.5);

  @override
  void validate(EntityCheck check) {
    final entity = check.entity;
    final scope = check.scope;
    final out = check.out;
    requireText(entity, scope, out, 'what');
    final howMany = entity.integer('count');
    if (howMany != null && howMany <= 0) {
      out.add(
        LevelIssue(
          Severity.warning,
          'gives $howMany of what it holds, so walking over it does nothing',
          where: scope.describe(entity),
        ),
      );
    }
  }

  @override
  void spawn(EntitySpawn spawn) {
    final entity = spawn.entity;
    final context = spawn.context;
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
