import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import '../physics/layers.dart';
import 'heightfield.dart';
import 'level.dart';
import 'level_validator.dart';
import 'spawn_context.dart';

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
  ///
  /// **The ground goes in too.** A level's field of heights was drawn and
  /// walked on by nothing: this added the brushes and stopped, so a body on a
  /// level that had only a field fell through the picture of a hill. The shape
  /// for it had existed for some time, tested against this same field's
  /// diagonal, and no caller ever built one.
  ///
  /// With the level's recipes expanded: a wall a recipe stands for is a wall
  /// a body stops at.
  void addTo(CollisionWorld world) {
    if (heightfield case final ground?) world.add(_groundCollider(ground));
    for (final brush in expandRecipes(this).brushes) {
      if (!brush.solid) continue;
      final ramp = brush.ramp;
      world.add(
        Collider(
          // A ramp is a brush with a corner cut off, and the difference is the
          // whole of what makes it walkable: a wedge's low end is an edge, and
          // a box's is a wall as tall as the brush.
          shape: ramp == null
              ? CollisionBox(brush.halfExtents)
              : CollisionWedge(brush.halfExtents, uphill: ramp),
          position: brush.centre,
          // The document's own bit when it names one. A one-way platform, a
          // grate, a wall only some bodies respect: all of them are a brush on
          // a layer of its own, and the level format was the one place that
          // could not say so.
          layer: brush.layer ?? CollisionLayers.world,
          userData: brush,
        ),
      );
    }
  }

  /// The ground as one static collider, standing where it is drawn.
  ///
  /// **The field is described from a corner and the shape from its middle**,
  /// and this is the one place the two are reconciled. `CollisionHeightfield`
  /// is centred on its collider, for the broadphase's sake, and lifts its
  /// samples so that the middle of their range sits at the collider's height.
  /// Putting the collider at the field's centre in X and Z, and at the middle
  /// of the samples' range in Y, therefore gives every sample back its own
  /// number as a world height, which is what [Heightfield.heightAt] and the
  /// drawn mesh both take it to be.
  ///
  /// **`origin.y` is left out on purpose**, because those two leave it out:
  /// neither adds it to a sample, so a field lifted by its origin would be a
  /// ground the body stands above. If the format ever starts honouring it, the
  /// three change together.
  ///
  /// The collider's `userData` is the [Heightfield], for the reason a brush's
  /// is the [Brush].
  Collider _groundCollider(Heightfield ground) {
    final shape = CollisionHeightfield(
      columns: ground.columns,
      rows: ground.rows,
      cellSize: ground.cellSize,
      heights: ground.copyOfSamples(),
    );
    return Collider(
      shape: shape,
      position: Vector3(
        ground.origin.x + ground.width * 0.5,
        (shape.highest + shape.lowest) * 0.5,
        ground.origin.z + ground.depth * 0.5,
      ),
      layer: CollisionLayers.world,
      userData: ground,
    );
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
