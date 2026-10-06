import 'package:flutter3d_sim/flutter3d_sim.dart'
    show CollisionBox, CollisionWorld, Collider;
import 'package:vector_math/vector_math.dart';

import 'voxel_boxes.dart';
import 'voxel_world.dart';

/// A [VoxelWorld]'s blocks in a [CollisionWorld], as static boxes, chunk by
/// chunk.
///
/// **Boxes in an ordinary world, not a voxel shape**, so that everything
/// already able to collide with a level — a character controller, a ray, a
/// rigid body — collides with blocks without learning what one is. A world
/// attached to the native core mirrors its statics by revision, and an edit
/// that replaces a chunk's boxes bumps it: the core collides with the
/// blocks as they now are from the next `update` on, with nothing
/// voxel-shaped in it either.
///
/// An edit costs its chunk's boxes and nothing else — see [refresh].
final class VoxelCollision {
  /// Adds every chunk of [voxels] to [world], on [layer].
  VoxelCollision(this.voxels, this.world, {this.layer = 1 << 0}) {
    for (final chunk in voxels.chunks) {
      _build(chunk);
    }
  }

  /// The blocks collided with.
  final VoxelWorld voxels;

  /// Where their boxes are.
  final CollisionWorld world;

  /// The layer every box is on — bit zero, which a game usually calls its
  /// world, unless it says otherwise.
  final int layer;

  final Map<ChunkKey, List<Collider>> _colliders = <ChunkKey, List<Collider>>{};

  /// How many boxes stand for the whole world.
  int get boxCount => _colliders.values.fold(
    0,
    (int sum, List<Collider> boxes) => sum + boxes.length,
  );

  /// [chunk]'s boxes in [world], for a test or a debug view to look at.
  List<Collider> collidersOf(ChunkKey chunk) =>
      List<Collider>.unmodifiable(_colliders[chunk] ?? const <Collider>[]);

  /// Replaces the boxes of every chunk in [chunks] with ones built from the
  /// blocks as they now are — what a game calls with
  /// `VoxelChanges.chunks` after an edit.
  void refresh(Iterable<ChunkKey> chunks) {
    for (final chunk in chunks) {
      for (final collider in _colliders.remove(chunk) ?? const <Collider>[]) {
        world.remove(collider);
      }
      _build(chunk);
    }
  }

  /// Takes every box out of [world], for a game leaving the level.
  void dispose() {
    for (final boxes in _colliders.values) {
      for (final collider in boxes) {
        world.remove(collider);
      }
    }
    _colliders.clear();
  }

  void _build(ChunkKey chunk) {
    final boxes = boxesOf(voxels, chunk);
    if (boxes.isEmpty) return;
    _colliders[chunk] = <Collider>[
      for (final box in boxes)
        world.add(
          Collider(
            shape: CollisionBox(
              Vector3(
                (box.maxX - box.minX) / 2.0,
                (box.maxY - box.minY) / 2.0,
                (box.maxZ - box.minZ) / 2.0,
              ),
            ),
            position: Vector3(
              (box.minX + box.maxX) / 2.0,
              (box.minY + box.maxY) / 2.0,
              (box.minZ + box.maxZ) / 2.0,
            ),
            layer: layer,
            userData: chunk,
          ),
        ),
    ];
  }
}
