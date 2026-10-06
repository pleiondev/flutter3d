/// A world of blocks for a game to stand on, dig into and build with.
///
/// * [VoxelWorld] holds them, a byte a voxel in chunks of sixteen cubed,
///   drawn from a seeded [VoxelTerrain] and edited block by block. Its
///   [VoxelWorld.toJson] is the seed and the edits, never the blocks.
/// * [meshChunk] turns a chunk's visible faces into `MeshData`, one mesh a
///   material, merged greedily.
/// * [VoxelCollision] keeps a `CollisionWorld` on the blocks as boxes merged
///   greedily, chunk by chunk — on the native core too, once the world is
///   attached to it.
/// * [VoxelNavigation] keeps a tiled navigation mesh on them, baking again
///   only the tiles an edit reaches.
/// * [VoxelRays.raycast] finds the block a player looks at.
///
/// An edit is one call and the consumers each take what changed:
///
/// ```dart
/// world.edit(x, y, z, Voxels.empty);
/// final changes = world.takeChanges();
/// collision.refresh(changes.chunks);
/// navigation.follow(changes);
/// for (final chunk in changes.surfaces) {
///   upload(chunk, meshChunk(world, chunk));
/// }
/// ```
library;

import 'src/voxel_collision.dart';
import 'src/voxel_mesher.dart';
import 'src/voxel_navigation.dart';
import 'src/voxel_ray.dart';
import 'src/voxel_terrain.dart';
import 'src/voxel_world.dart';

export 'src/voxel_boxes.dart';
export 'src/voxel_collision.dart';
export 'src/voxel_mesher.dart';
export 'src/voxel_navigation.dart';
export 'src/voxel_ray.dart';
export 'src/voxel_terrain.dart';
export 'src/voxel_world.dart';
