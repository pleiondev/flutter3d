import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import '../collectible.dart';

/// A key on the floor.
///
/// The type is the *format's* `key`, not one of this genre's, and that is not
/// an accident: `LevelScope` gathers keys to answer whether a locked door names
/// one that exists, so a game that invents its own word for them loses the
/// validator's help and ships levels with doors nothing opens.
///
/// What it spawns is an ordinary [Collectible] that also grants a key — the
/// walking-over-it half is identical and only where it lands differs.
final class KeyKind extends EntityKind {

  /// A player has to be able to get to one of these. See
  /// [EntityKind.mustBeReachable] — and the fourteen that were inside walls.
  @override
  bool get mustBeReachable => true;
  const KeyKind() : super(EntityTypes.key);

  static Vector3 get defaultSize => Vector3(0.5, 0.5, 0.5);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    requireText(entity, scope, out, 'color');
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final colour = entity.string('color');
    if (colour == null) return;
    final collider = place(
      entity,
      context,
      kind: ColliderKind.trigger,
      layer: CollisionLayers.pickup,
      mask: CollisionLayers.player,
      fallbackSize: defaultSize,
    );
    final key = context.mechanisms.add(
      Collectible(
        name: entity.name,
        what: 'key',
        key: colour,
        collider: collider,
      ),
    );
    context.reveal(
      entity,
      collider: collider,
      mechanism: key,
      size: entity.vector('size') ?? defaultSize,
    );
  }
}
