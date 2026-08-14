import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'level.dart';
import 'level_validator.dart';
import 'spawn_context.dart';
import '../physics/layers.dart';

/// Building the physical side of a level.
///
/// An extension rather than a builder class: there is one sensible way to turn
/// brushes into colliders, it needs no configuration, and `level.addTo(world)`
/// says what happens without inventing a noun for it.
extension LevelCollision on Level {
  /// Adds every solid brush to [world] as a static collider.
  ///
  /// Non-solid brushes are skipped, which is the whole point of the flag: a
  /// decorative moulding should be visible and not something to catch on.
  ///
  /// The collider's `userData` is the [Brush], so a query can trace a contact
  /// back to what was authored — which is what the editor's "what did I just
  /// click" needs, and what a footstep sound needs to know it is stone.
  void addTo(CollisionWorld world) {
    for (final brush in brushes) {
      if (!brush.solid) continue;
      world.add(
        Collider(
          shape: CollisionBox(brush.halfExtents),
          position: brush.centre,
          layer: CollisionLayers.world,
          userData: brush,
        ),
      );
    }
  }

  /// Turns every entity into whatever its kind says it is.
  ///
  /// Beside [addTo] because the two are the same job on the two halves of a
  /// level: the brushes become colliders, and the entities become actors. An
  /// unknown type is skipped rather than fatal — the validator has already
  /// refused the level if it mattered, and a tool loading a broken document to
  /// repair it should still see everything it can.
  void spawnInto(SpawnContext context, {required EntityRegistry registry}) {
    final kinds = registry;
    for (final entity in entities) {
      kinds[entity.type]?.spawn(entity, context);
    }
  }

  /// Where the player starts, and which way they face.
  ///
  /// Null when there is no spawn, which [LevelValidator] reports as an error —
  /// this returns rather than throws so a tool can load a broken level in order
  /// to fix it.
  ({Vector3 position, double yaw})? get playerStart {
    for (final entity in entities) {
      if (entity.type == EntityTypes.playerSpawn) {
        return (position: entity.position.clone(), yaw: entity.yaw);
      }
    }
    return null;
  }
}
