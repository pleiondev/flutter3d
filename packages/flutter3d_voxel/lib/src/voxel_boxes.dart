import 'dart:typed_data';

import 'voxel_world.dart';

/// [chunk]'s solid voxels as the fewest boxes a greedy sweep finds, each
/// voxel in exactly one — whatever it is made of.
///
/// A box grows from the first voxel not yet covered: along x while the next
/// voxel is solid and free, then along z while the whole next row is, then
/// along y while the whole next slab is. Not the fewest boxes there could
/// be — that is a hard problem — but a field of terrain comes out as a box a
/// run of equal columns, and a solid chunk as one box.
///
/// What a chunk collides with and what its navigation is baked from: a
/// character's sweep and a lattice's rasteriser each cost a box, not a
/// voxel.
List<VoxelBox> boxesOf(VoxelWorld world, ChunkKey chunk) {
  const n = VoxelWorld.chunkSize;
  final ox = chunk.x * n, oy = chunk.y * n, oz = chunk.z * n;
  final taken = Uint8List(n * n * n);
  int cell(int x, int y, int z) => (y * n + z) * n + x;
  bool free(int x, int y, int z) =>
      taken[cell(x, y, z)] == 0 && world.isSolid(ox + x, oy + y, oz + z);
  bool rowFree(int x0, int x1, int y, int z) {
    for (var x = x0; x < x1; x++) {
      if (!free(x, y, z)) return false;
    }
    return true;
  }

  bool slabFree(int x0, int x1, int z0, int z1, int y) {
    for (var z = z0; z < z1; z++) {
      if (!rowFree(x0, x1, y, z)) return false;
    }
    return true;
  }

  final boxes = <VoxelBox>[];
  for (var y = 0; y < n; y++) {
    for (var z = 0; z < n; z++) {
      for (var x = 0; x < n; x++) {
        if (!free(x, y, z)) continue;
        var x1 = x + 1;
        while (x1 < n && free(x1, y, z)) {
          x1++;
        }
        var z1 = z + 1;
        while (z1 < n && rowFree(x, x1, y, z1)) {
          z1++;
        }
        var y1 = y + 1;
        while (y1 < n && slabFree(x, x1, z, z1, y1)) {
          y1++;
        }
        for (var by = y; by < y1; by++) {
          for (var bz = z; bz < z1; bz++) {
            taken.fillRange(cell(x, by, bz), cell(x1, by, bz), 1);
          }
        }
        boxes.add((
          minX: ox + x,
          minY: oy + y,
          minZ: oz + z,
          maxX: ox + x1,
          maxY: oy + y1,
          maxZ: oz + z1,
        ));
      }
    }
  }
  return boxes;
}
